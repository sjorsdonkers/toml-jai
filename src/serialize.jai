serialize :: (input: $T) -> ok:=false, toml:string="" {
    a := scoped_pool();
    ok, value := type_to_value_shared_memory(input,, a); if !ok return;
    builder: String_Builder;
    print_table_to_builder(*builder, value,, a);
    return true, builder_to_string(*builder);
}

type_to_value :: (input: $T) -> ok:=false, value:Value=.{} {
    ok, value := type_to_value_shared_memory(input,, scoped_pool()); if !ok return;
    return ok, copy(value); // Would be nice if we could just copy the reused strings and Value arrays and tables.
}

type_to_value_shared_memory :: (data: $T) -> ok:=false, toml:Value=.{} {
    info :: type_info(T);
    done, custom_ok, custom_value := custom_type_to_value(data, type_info(T));
    if done return custom_ok, custom_value;

    #if info.type == {
    case .INTEGER; #if T == u64 if data > 0x7fff_ffff_ffff_ffff { return_with_error("Value % is out of s64 range", data); }
                  return true, .{type = .INT,    int_value    = data.(s64, no_check)};
    case .FLOAT;  return true, .{type = .FLOAT,  float_value  = xx data};
    case .BOOL;   return true, .{type = .BOOL,   bool_value   = data};
    case .STRING; return true, .{type = .STRING, string_value = data}; // No deep copy!
    case .POINTER;
        if data == null return true, context.toml_null_value; // User can change default null value as module parameter
        ok, value := type_to_value_shared_memory(data.*);
        return ok, value;
    case .VOID;  return true, .{};
    case .STRUCT;
        if info.textual_flags & .UNION return_with_error("Untagged unions (%) are not supported, as we cannot determine the active member, use @SumType", ifx info.name then info.name else "anonymous");

        // Unlike Basic.print we do re-print all overlapping #place members. This will output the same data multiple times, but is likely more predictable.
        // Otherwise we would need to recursively track to check whether the offset is always increasing compared to the highest offset.
        table: [..]KeyValue;
        ok: bool;
        member_value: Value;
        #insert -> string {
            builder: String_Builder;
            for member: info.members {
                if member.flags & (.CONSTANT | .IMPORTED) continue;
                if member.name {
                    print_to_builder(*builder, "ok, member_value = type_to_value_shared_memory(data.%);  if !ok return;\n", member.name); // can always do anon version
                    print_to_builder(*builder, "array_add(*table, KeyValue.{key=\"%\", value=member_value});\n"           , member.name);
                } else {
                    print_to_builder(*builder, "anon_type_%1    :: #run cast(*Type, *info.members[%1].type).*;\n"                          , it_index);
                    print_to_builder(*builder, "anon_value_%1   := ((*data).(*void) + info.members[%1].offset_in_bytes).(*anon_type_%1);\n", it_index);
                    print_to_builder(*builder, "ok, member_value = type_to_value_shared_memory(anon_value_%1.*);  if !ok return;\n"        , it_index);
                    print_to_builder(*builder, "array_add(*table, KeyValue.{key=\"\", value=member_value});\n");
                }
            }
            return builder_to_string(*builder);
        }
        return true, .{type=.TABLE, table=table};
    case .ARRAY;
        array: [..]Value;
        array_reserve(*array, data.count);
        for data {
            ok, record_value:= type_to_value_shared_memory(it); if !ok return;
            array_add(*array, record_value);
        }
        return true, .{type=.ARRAY, array=array};
    case .ANY;
        if data.value_pointer == null return true, context.toml_null_value; // Similar to null pointer
        ok, value:= type_to_value_shared_memory(data.value_pointer, data.type);
        return ok, value;
    case .ENUM;
        for info.values  if it == data.(s64) {
            return true, .{type=.STRING, string_value=info.names[it_index]};
        }
        return_with_error("Enum value % not found in enum %", data, info.name);
    case .VARIANT;
        base_type :: #run cast(*Type, *info.variant_of).*;
        ok, value:= type_to_value_shared_memory(data.(base_type));
        return ok, value;
    }
    return_with_error("Parsing of type % is not supported", info.type);
}

// NOTE: Does not deep copy!
// Not meant to be called directly by the user, but instead to be used inside custom serializers.
type_to_value_shared_memory :: (slot: *void, info: *Type_Info) -> ok:=false, toml:Value=.{} {
    done, ok, value := context.toml_custom_type_to_value(slot, info);
    if done return ok, value;

    if #complete info.type == {
    case .INTEGER;
        ok, value := get_integer_value(slot, xx info); if !ok return;
        return true, .{type=.INT, int_value=value};
    case .FLOAT;
        if      info.runtime_size == 4 { return true, .{type=.FLOAT, float_value=cast(*float32, slot).*}; }
        else if info.runtime_size == 8 { return true, .{type=.FLOAT, float_value=cast(*float64, slot).*}; }
        else { assert(false, "Unsupported float size %", info.runtime_size); }
    case .BOOL;   return true, .{type=.BOOL, bool_value=cast(*bool, slot).*};
    case .STRING; return true, .{type=.STRING, string_value=cast(*string, slot).*}; // No deep copy!
    case .POINTER;
        if cast(**void, slot).* == null return true, context.toml_null_value; // User can change default null value as module parameter
        ok, value := type_to_value_shared_memory(cast(**void, slot).*, cast(*Type_Info_Pointer, info).pointer_to);
        return ok, value;
    case .VOID;  return true, .{};
    case .STRUCT;
        struct_info :*Type_Info_Struct= xx info;
        if struct_info.textual_flags & .UNION return_with_error("Untagged unions (%) are not supported, as we cannot determine the active member, use @SumType", ifx struct_info.name then struct_info.name else "anonymous");

        // Unlike Basic.print we do re-print all overlapping #place members. This will output the same data multiple times, but is likely more predictable.
        // Otherwise we would need to recursively track to check whether the offset is always increasing compared to the highest offset.
        table: [..]KeyValue;
        for member: struct_info.members {
            if member.flags & (.CONSTANT | .IMPORTED) continue;
            ok, member_value:= type_to_value_shared_memory(slot + member.offset_in_bytes, member.type);  if !ok return;
            array_add(*table, KeyValue.{key=member.name, value=member_value});
        }
        return true, .{type=.TABLE, table=table};
    case .ARRAY;
        array_info :*Type_Info_Array= xx info;
        array_count:= ifx array_info.array_type == .FIXED then array_info.array_count else cast(*s64,   slot).*;
        array_slot := ifx array_info.array_type == .FIXED then slot                   else cast(**void, slot+8).*;

        array: [..]Value;
        array_reserve(*array, array_count);
        for idx: 0..array_count-1 {
            element_slot := array_slot + array_info.element_type.runtime_size * idx;
            ok, record_value:= type_to_value_shared_memory(element_slot, array_info.element_type); if !ok return;
            array_add(*array, record_value);
        }
        return true, .{type=.ARRAY, array=array};
    case .ANY;
        any_value :*Any_Struct= xx slot;
        if any_value.value_pointer == null return true, context.toml_null_value; // Similar to null pointer
        ok, value := type_to_value_shared_memory(any_value.value_pointer, any_value.type);
        return ok, value;
    case .ENUM;
        enum_info :*Type_Info_Enum= xx info;
        enum_value:= Reflection.get_enum_value(slot, enum_info);
        for enum_info.values  if it == enum_value {
            return true, .{type=.STRING, string_value=enum_info.names[it_index]};
        }
        return_with_error("Enum value % not found in enum %", enum_value, enum_info.name);
    case .VARIANT;
        ok, value:= type_to_value_shared_memory(slot, cast(*Type_Info_Variant, info).variant_of);
        return ok, value;
    case .PROCEDURE; #through;  case .OVERLOAD_SET; #through;  case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;      #through;  case .CODE;         #through;  case .UNTYPED_LITERAL;      #through;
    case .UNTYPED_ENUM;
    }
    return_with_error("Parsing of type % is not supported", info.type);
}

// custom_type_info :: (info: *Type_Info) -> *Type_Info {

// }

// custom_type_to_value :: (data: Value, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, data; // No deep copy!
// }
// custom_type_to_value :: (data: Chrono, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, .{type=.DATETIME, datetime=data};
// }
// custom_type_to_value :: (data: Time, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, .{type=.LOCAL_TIME, time=data};
// }
// custom_type_to_value :: (data: Date, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, .{type=.LOCAL_DATE, date=data};
// }
// custom_type_to_value :: (data: DateTime, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, .{type=.LOCAL_DATETIME, datetime=data};
// }
// custom_type_to_value :: (data: DateTimeOffset, $info: *Type_Info) -> done:bool, ok:bool, toml:Value {
//     return true, true, .{type=.OFFSET_DATETIME, datetime_offset=data};
// }

custom_type_to_value :: (data: $T, $info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    #if T == {
    case Value;          return true, true, data; // No deep copy!
    case Chrono;         return true, true, .{type=.DATETIME, datetime=data};
    case Time;           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_TIME, time=data}};
    case Date;           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATE, date=data}};
    case DateTime;       return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATETIME, datetime=data}};
    case DateTimeOffset; return true, true, .{type=.DATETIME, datetime=.{type=.OFFSET_DATETIME, datetime_offset=data}};
    }

    #if info.type != .STRUCT return false;
    struct_info :*Type_Info_Struct: xx info;
    #if #run array_find(struct_info.notes, "SumType") {
        ok, sumtype_value:= sumtype_to_value2(data, struct_info); return true, ok, sumtype_value;
    }
    return false;
}

sumtype_to_value2 :: (data: $T, $info: *Type_Info_Struct) -> ok:=false, value:Value=.{} {
    #insert -> string {
        valid, tag_member, union_member, tag_info, union_info := is_valid_sumtype(info);
        assert(valid, "SumType % is not valid", info.name);

        // tag_member   = "info.members[0]";
        // union_member = "info.members[1]";

        builder: String_Builder;
        append(*builder,#string DONE
Tag_Type  :: #run cast(*Type, *info.members[0].type).*;
tag_value := ((*data).(*void) + info.members[0].offset_in_bytes).(*Tag_Type);

table: [..]KeyValue;
if #complete tag_value.* == {
DONE);
        for tag: tag_info.names {
            print_to_builder(*builder, #string DONE
case .%2;
    Variant_Type      :: #run cast(*Type, *info.members[1].type.(*Type_Info_Struct).members[%1].type).*;
    variant_data      := ((*data).(*void) + info.members[1].offset_in_bytes + info.members[1].type.(*Type_Info_Struct).members[%1].offset_in_bytes).(*Variant_Type);
    ok, variant_value := type_to_value_shared_memory(variant_data.*);  if !ok return;
    array_add(*table, KeyValue.{key="%2", value=variant_value});
DONE, it_index, tag);

            // We use the enums string name as key as the union member may be anonymous
        }
        append(*builder, "}\nreturn true, .{type=.TABLE, table=table};");
        return builder_to_string(*builder);
    }
}

default_custom_type_to_value :: (slot: *void, info: *Type_Info) -> done:bool, ok:bool, toml:Value {
    if info.type != .STRUCT return false, true, .{};
    struct_info :*Type_Info_Struct= xx info;

    if struct_info == {
    case type_info(Value);          return true, true, cast(*Value, slot).*; // No deep copy!
    case type_info(Chrono);         return true, true, .{type=.DATETIME, datetime=cast(*Chrono, slot).*};
    case type_info(Time);           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_TIME,      time=           cast(*Time, slot).*}};
    case type_info(Date);           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATE,      date=           cast(*Date, slot).*}};
    case type_info(DateTime);       return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATETIME,  datetime=       cast(*DateTime, slot).*}};
    case type_info(DateTimeOffset); return true, true, .{type=.DATETIME, datetime=.{type=.OFFSET_DATETIME, datetime_offset=cast(*DateTimeOffset, slot).*}};
    }
    if array_find(struct_info.notes, "SumType") { ok, sumtype_value:= sumtype_to_value(slot, struct_info); return true, ok, sumtype_value; }

    return false, true, .{};
}

sumtype_to_value :: (slot: *void, struct_info: *Type_Info_Struct) -> ok:=false, value:Value=.{} {
    valid, tag_member, union_member, tag_info, union_info := is_valid_sumtype(struct_info);
    if !valid { return_with_error("SumType % is not valid", struct_info.name); }

    active_tag_idx := Reflection.get_enum_value(slot + tag_member.offset_in_bytes, xx tag_member.type);
    active_variant := union_info.members[active_tag_idx];
    variant_slot   := slot + union_member.offset_in_bytes + active_variant.offset_in_bytes;

    ok, union_value := type_to_value_shared_memory(variant_slot, active_variant.type); if !ok return;
    table: [..]KeyValue;
    array_add(*table, .{key=tag_info.names[active_tag_idx], value=union_value}); // We use the enums string name as the union member may be anonymous
    return true, .{type=.TABLE, table=table};
}

print_table_to_builder :: (builder: *String_Builder, value: Value, parent_key: string = "") {
    assert(value.type == .TABLE, "Only tables can be serialized at the top level, got %", value.type);
    // Key=Value pairs
    for value.table  if !is_table_header(it.value) && !is_array_of_tables(it.value) {
        print_keyvalue_to_builder(builder, it);
        append(builder, "\n");
    }
    // [Table.Header]
    for value.table  if is_table_header(it.value) {
        dotted_key := build_dotted_key(parent_key, it.key);
        next_is_header := true; // Do not start a [table.header] yet if the next table is also a table header
        for it.table if !is_table_header(it.value) { next_is_header = false; break; }
        if !next_is_header {
            append(builder, "[");
            append(builder, dotted_key);
            append(builder, "]\n");
        }
        print_table_to_builder(builder, it.value, dotted_key);
    }
    // [[Array.Of.Tables.Header]]
    for value.table  if is_array_of_tables(it.value) {
        dotted_key := build_dotted_key(parent_key, it.key);
        for it.array {
            append(builder, "[[");
            append(builder, dotted_key);
            append(builder, "]]\n");
            print_table_to_builder(builder, it, dotted_key);
        }
    }
}

print_keyvalue_to_builder :: (builder: *String_Builder, key_value: KeyValue) {
    // Recursively print a dotted key
    print_to_builder_escaped(builder, key_value.key, true);
    if key_value.type == .TABLE && key_value.table.count == 1 {
        append(builder, ".");
        print_keyvalue_to_builder(builder, key_value.table[0]);
        return;
    } // If this is a table with multiple values we print it as an inline table.

    // We print the value inside this procedure as only the very last value needs to be printed
    append(builder, "=");
    print_inline_value_to_builder(builder, key_value.value);
}

print_inline_value_to_builder :: (builder: *String_Builder, value: Value) {
    if #complete value.type == {
    case .BOOL; print_item_to_builder(builder, value.bool_value);
    case .INT;  print_item_to_builder(builder, value.int_value);
    case .FLOAT;
        is_nan, is_inf:= is_nan_is_inf(value.float_value);
        if is_nan || is_inf {
            if (cast(*u64, *value.float_value).* & 0x8000_0000_0000_0000) { append(builder, "-"); }
            if is_nan { append(builder, "nan"); } else { append(builder, "inf"); }
            return;
        }
        print_item_to_builder(builder, value.float_value);
    case .STRING;   print_to_builder_escaped(builder, value.string_value, false);
    case .DATETIME; print_datetime_to_builder(builder, value.datetime);
    case .ARRAY;
        append(builder, "[");
        for value.array {
            print_inline_value_to_builder(builder, it);
            if it_index + 1 != value.array.count then append(builder, ", ");
        }
        append(builder, "]");
    case .TABLE;
        append(builder, "{");
        for value.table {
            print_keyvalue_to_builder(builder, it);
            if it_index + 1 != value.table.count then append(builder, ", ");
        }
        append(builder, "}");
    }
}

print_to_builder_escaped :: (builder: *String_Builder, str: string, $is_key: bool) {
    #if is_key { if is_bare_key(str) { append(builder, str); return; } }

    append(builder, "\""); // TODO consider single ' and multiline strings, Note multiline should impact is_inline_table
	for str if it == {
        case #char "\x08"; append(builder, "\\b");
        case #char "\t";   append(builder, "\\t");
        case #char "\n";   append(builder, "\\n");
        case #char "\x0c"; append(builder, "\\f");
        case #char "\r";   append(builder, "\\r");
        case #char "\"";   append(builder, "\\\"");
        case #char "\\";   append(builder, "\\\\");
        case;              append(builder, it);
    }
    append(builder, "\"");
}

// true if it would otherwise introduce additional braces or brackets, so no in-line tables or arrays in in-line tables,
// additionally also not: a = {b.c = 1, b.d = 2, e = 3} as it is equivalent to: a = { b= {c = 1, d = 2}, e = 3}
is_table_header :: (value: Value) -> bool {
    is_inline_table :: (table: []KeyValue) -> bool {
        for table if it.type == .TABLE || it.type == .ARRAY then return false;
        return true;
    }
    is_single_value :: (table: []KeyValue) -> bool {
        if is_inline_table(table)  return true;
        if table.count != 1        return false;
        if table[0].type == .TABLE return is_single_value(table[0].table);
        if table[0].type == .ARRAY return false;
        return true;
    }
    if value.type != .TABLE return false;
    return !is_single_value(value.table);
}

// true if all elements are tables of any kind
is_array_of_tables :: (value: Value) -> bool {
    if value.type != .ARRAY return false;
    if value.array.count == 0 return false;
    for value.array if it.type != .TABLE return false;
    return true;
}

build_dotted_key :: (parent_key: string, key: string) -> string {
    key_builder: String_Builder;
    if parent_key {
        append(*key_builder, parent_key);
        append(*key_builder, ".");
    }
    print_to_builder_escaped(*key_builder, key, true);
    return builder_to_string(*key_builder);
}

#scope_file
#import "Basic";
#import "Math";
#import "Compiler";
Reflection :: #import "Reflection";
