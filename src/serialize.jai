serialize :: (input: $T) -> ok:=false, toml:string="" {
    a := scoped_pool();
    ok, value := type_to_value(*input, type_info(T),, a); if !ok return;
    builder: String_Builder;
    serialize(*builder, value,, a);
    return true, builder_to_string(*builder);
}

type_to_value :: (input: $T) -> ok:=false, value:Value=.{} {
    ok, value := type_to_value(*input, type_info(T),, scoped_pool()); if !ok return;
    return ok, copy(value);
}

#scope_module

// Note: Does not deep copy
type_to_value :: (slot: *void, info: *Type_Info) -> ok:=false, toml:Value=.{} {
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
        assert(cast(**void, slot) != null, "Implementation error: null pointers should be filtered out");
        ok, value := type_to_value(cast(**void, slot).*, cast(*Type_Info_Pointer, info).pointer_to);
        return ok, value;
    case .VOID;  return true, .{};
    case .STRUCT;
        struct_info :*Type_Info_Struct= xx info;
        if struct_info == {
        case type_info(Value);          return true, cast(*Value, slot).*; // No deep copy!
        case type_info(Chrono);         return true, .{type=.DATETIME, datetime=cast(*Chrono, slot).*};
        case type_info(Time);           return true, .{type=.DATETIME, datetime=.{type=.LOCAL_TIME,      time=           cast(*Time, slot).*}};
        case type_info(Date);           return true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATE,      date=           cast(*Date, slot).*}};
        case type_info(DateTime);       return true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATETIME,  datetime=       cast(*DateTime, slot).*}};
        case type_info(DateTimeOffset); return true, .{type=.DATETIME, datetime=.{type=.OFFSET_DATETIME, datetime_offset=cast(*DateTimeOffset, slot).*}};
        }

        if array_find(struct_info.notes, "SumType") {
            ok, sumtype_value:= sumtype_to_value(slot, struct_info);
            return ok, sumtype_value;
        }
        if struct_info.textual_flags & .UNION return_with_error("Untagged unions (%) are not supported, as we cannot determine the active member, use @SumType", ifx struct_info.name then struct_info.name else "anonymous");

        // Unlike Basic.print we do re-print all overlapping #place members. This will output the same data multiple times, but is likely more predictable.
        // Otherwise we would need to recursively track the offset is always increase compared to the highest offset.
        table: [..]KeyValue;
        for member: struct_info.members {
            if member.flags & (.CONSTANT | .IMPORTED)              continue;
            if is_null(slot + member.offset_in_bytes, member.type) continue;
            ok, member_value:= type_to_value(slot + member.offset_in_bytes, member.type);  if !ok return;
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
            element_slot:= array_slot + array_info.element_type.runtime_size * idx;
            if is_null(element_slot, array_info.element_type) return_with_error("Null pointer in array detected which is not supported");
            ok, record_value:= type_to_value(element_slot, array_info.element_type); if !ok return;
            array_add(*array, record_value);
        }
        return true, .{type=.ARRAY, array=array};
    case .ANY;
        any_value :*Any_Struct= xx slot;
        assert(any_value.value_pointer != null, "Implementation error: null pointers should be filtered out");
        ok, value:= type_to_value(any_value.value_pointer, any_value.type);
        return ok, value;
    case .ENUM;
        enum_info :*Type_Info_Enum= xx info;
        for enum_info.values  if it == get_enum_value(slot, enum_info) {
            return true, .{type=.STRING, string_value=enum_info.names[it_index]};
        }
        assert(false, "Enum value % not found in enum %", get_enum_value(slot, enum_info), enum_info.name);
    case .VARIANT;
        ok, value:= type_to_value(slot, cast(*Type_Info_Variant, info).variant_of);
        return ok, value;
    case .PROCEDURE;            #through;
    case .OVERLOAD_SET;         #through;
    case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;                 #through;
    case .CODE;                 #through;
    case .UNTYPED_LITERAL;      #through;
    case .UNTYPED_ENUM;
    }
    return_with_error("Parsing of type % is not supported", info.type);
}

sumtype_to_value :: (slot: *void, struct_info: *Type_Info_Struct) -> ok:=false, value:Value=.{} {
    valid, tag_member, union_member, tag_info, union_info:= is_valid_sumtype(struct_info);
    if !valid { return_with_error("SumType % is not valid", struct_info.name); }

    active_tag_idx:= get_enum_value(slot + tag_member.offset_in_bytes, xx tag_member.type);
    active_variant:= union_info.members[active_tag_idx];
    variant_slot:= slot + union_member.offset_in_bytes + active_variant.offset_in_bytes;
    if is_null(variant_slot, active_variant.type) return_with_error("Null pointer in SumType detected which is not supported");

    ok, union_value:= type_to_value(variant_slot, active_variant.type); if !ok return;
    table: [..]KeyValue;
    array_add(*table, .{key=tag_info.names[active_tag_idx], value=union_value}); // We use the enums string name as the union member may be anonymous
    return true, .{type=.TABLE, table=table};
}

is_null :: (slot: *void, info: *Type_Info) -> bool {
    if info.type == .POINTER return cast(**void, slot).* == null;
    if info.type == .ANY     return cast(*Any_Struct, slot).value_pointer == null;
    return false;
}

serialize :: (builder: *String_Builder, value: Value, parent_key: string = "") {
    assert(value.type == .TABLE, "Only tables can be serialized at the top level, got %", value.type);
    // Key=Value pairs
    for value.table  if !is_table_header(it.value) && !is_array_of_tables(it.value) {
        print_single_keyvalue(builder, it);
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
        serialize(builder, it.value, dotted_key);
    }
    // [[Array.Of.Tables.Header]]
    for value.table  if is_array_of_tables(it.value) {
        dotted_key := build_dotted_key(parent_key, it.key);
        for it.array {
            append(builder, "[[");
            append(builder, dotted_key);
            append(builder, "]]\n");
            serialize(builder, it, dotted_key);
        }
    }
}

serialize_inline :: (builder: *String_Builder, value: Value) {
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
            serialize_inline(builder, it);
            if it_index + 1 != value.array.count then append(builder, ", ");
        }
        append(builder, "]");
    case .TABLE;
        append(builder, "{");
        for value.table {
            print_single_keyvalue(builder, it);
            if it_index + 1 != value.table.count then append(builder, ", ");
        }
        append(builder, "}");
    }
}

print_to_builder_escaped :: (builder: *String_Builder, str: string, $is_key: bool) {
    #if is_key {
        if is_bare_key(str) { append(builder, str); return; }
    }
    // TODO consider single ' and multiline strings, Note multiline should impact is_inline_table
    append(builder, "\"");
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

print_single_keyvalue :: (builder: *String_Builder, key_value: KeyValue) {
    // Recursively print a dotted key
    print_to_builder_escaped(builder, key_value.key, true);
    if key_value.type == .TABLE && key_value.table.count == 1 {
        append(builder, ".");
        print_single_keyvalue(builder, key_value.table[0]);
        return;
    } // If this is a table with multiple values we print it as an inline table.

    // We print the value inside this procedure as only the very last value needs to be printed
    append(builder, "=");
    serialize_inline(builder, key_value.value);
}

//
// Generic memory utilities
//

get_integer_value :: (data: *void, info: *Type_Info_Integer) -> ok:=false, value:s64=0 {
    if info.signed {
        if info.runtime_size == {
            case 1; return true, cast(*s8,  data).*;
            case 2; return true, cast(*s16, data).*;
            case 4; return true, cast(*s32, data).*;
            case 8; return true, cast(*s64, data).*;
            case; assert(false); return;
        }
    } else {
        if info.runtime_size == {
            case 1; return true, cast(*u8,  data).*;
            case 2; return true, cast(*u16, data).*;
            case 4; return true, cast(*u32, data).*;
            case 8;
                output := cast(*u64, data).*;
                S64_MAX :u64:   0x7fff_ffff_ffff_ffff;
                if output > S64_MAX { return_with_error("Value % is out of s64 range", output); }
                return true, xx,no_check output;
            case; assert(false); return;
        }
    }
}

#scope_file
#import "Basic";
#import "Math";
