serialize :: (input: Any) -> ok:=false, toml:string="" {
    builder: String_Builder;
    ok := serialize_to_builder(*builder, input); if !ok return;
    return true, builder_to_string(*builder);
}

serialize_to_builder :: (builder: *String_Builder, input: Any) -> ok:=false {
    a := scoped_pool();
    ok, value := type_to_value_shared_memory(input,, a); if !ok return;

    if !builder.initialized init_string_builder(builder); // Initialize the builder to make sure it does not use `a`.
    print_table_to_builder(builder, value,, a);
    return true;
}

type_to_value :: (input: Any) -> ok:=false, value:Value=.{} {
    ok, value := type_to_value_shared_memory(input,, scoped_pool()); if !ok return;
    return ok, copy(value); // Would be nice if we could just copy the reused strings and Value arrays and tables.
}

// NOTE: Does not deep copy!
// Not meant to be called directly by the user, but instead to be used inside custom serializers.
type_to_value_shared_memory :: (input: Any) -> ok:=false, toml:Value=.{} {
    done, ok, value := context.toml.custom_type_to_value(input);
    if done return ok, value;

    slot := input.value_pointer;
    info := input.type;

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
        if cast(**void, slot).* == null return true, context.toml.null_value; // User can change default null value as module parameter
        ok, value := type_to_value_shared_memory(Any.{cast(*Type_Info_Pointer, info).pointer_to, cast(**void, slot).*});
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
            ok, member_value:= type_to_value_shared_memory(Any.{member.type, slot + member.offset_in_bytes});  if !ok return;
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
            ok, record_value:= type_to_value_shared_memory(Any.{array_info.element_type, element_slot}); if !ok return;
            array_add(*array, record_value);
        }
        return true, .{type=.ARRAY, array=array};
    case .ANY;
        any_value :*Any_Struct= xx slot;
        if any_value.value_pointer == null return true, context.toml.null_value; // Similar to null pointer
        ok, value:= type_to_value_shared_memory(Any.{any_value.type, any_value.value_pointer});
        return ok, value;
    case .ENUM;
        enum_info :*Type_Info_Enum= xx info;
        enum_value:= Reflection.get_enum_value(slot, enum_info);
        for enum_info.values  if it == enum_value {
            return true, .{type=.STRING, string_value=enum_info.names[it_index]};
        }
        return_with_error("Enum value % not found in enum %", enum_value, enum_info.name);
    case .VARIANT;
        ok, value:= type_to_value_shared_memory(Any.{cast(*Type_Info_Variant, info).variant_of, slot});
        return ok, value;
    case .PROCEDURE; #through;  case .OVERLOAD_SET; #through;  case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;      #through;  case .CODE;         #through;  case .UNTYPED_LITERAL;      #through;
    case .UNTYPED_ENUM;
    }
    return_with_error("Parsing of type % is not supported", info.type);
}

default_custom_type_to_value :: (input: Any) -> done:=true, ok:=false, toml:Value=.{} {
    if input.type.type != .STRUCT return false, true, .{};
    struct_info :*Type_Info_Struct= xx input.type;

    slot := input.value_pointer;
    if struct_info == {
    case type_info(Value);          return true, true, cast(*Value, slot).*; // No deep copy!
    case type_info(Chrono);         return true, true, .{type=.DATETIME, datetime=cast(*Chrono, slot).*};
    case type_info(Time);           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_TIME,      time=           cast(*Time, slot).*}};
    case type_info(Date);           return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATE,      date=           cast(*Date, slot).*}};
    case type_info(DateTime);       return true, true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATETIME,  datetime=       cast(*DateTime, slot).*}};
    case type_info(DateTimeOffset); return true, true, .{type=.DATETIME, datetime=.{type=.OFFSET_DATETIME, datetime_offset=cast(*DateTimeOffset, slot).*}};
    case type_info(FormatInt);      return true, true, .{type=.FORMAT_INT,   format_int  =cast(*FormatInt,   slot)};
    case type_info(FormatFloat);    return true, true, .{type=.FORMAT_FLOAT, format_float=cast(*FormatFloat, slot)};
    }
    if array_find(struct_info.notes, "SumType") { ok, sumtype_value:= sumtype_to_value(slot, struct_info); return true, ok, sumtype_value; }

    return false, true, .{};
}

sumtype_to_value :: (slot: *void, struct_info: *Type_Info_Struct) -> ok:=false, value:Value=.{} {
    valid, tag_member, union_member, tag_info, union_info:= is_valid_sumtype(struct_info);
    if !valid { return_with_error("SumType % is not valid", struct_info.name); }

    active_tag:= Reflection.get_enum_value(slot + tag_member.offset_in_bytes, xx tag_member.type);
    found, active_tag_idx := array_find(tag_info.values, active_tag); if !found { return_with_error("Active tag % not found in %", active_tag, tag_info.name); }
    active_variant:= union_info.members[active_tag_idx];
    variant_slot:= slot + union_member.offset_in_bytes + active_variant.offset_in_bytes;

    ok, union_value:= type_to_value_shared_memory(Any.{active_variant.type, variant_slot}); if !ok return;
    table: [..]KeyValue;
    array_add(*table, .{key=tag_info.names[active_tag_idx], value=union_value}); // We use the enums string name as the union member may be anonymous
    return true, .{type=.TABLE, table=table};
}

// NOTE: Print procedures after this use context.print_style for int/float formatting
print_table_to_builder :: (builder: *String_Builder, value: Value, parent_key:="", $root:=true) {
    assert(value.type == .TABLE, "Only tables can be serialized at the top level, got %", value.type);
    #if root {
        old_style := context.print_style;
        context.print_style = Print_Style.{default_format_float=context.toml.default_format_float, default_format_int=context.toml.default_format_int};
        defer context.print_style = old_style;
    }

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
        print_table_to_builder(builder, it.value, dotted_key, false);
    }
    // [[Array.Of.Tables.Header]]
    for value.table  if is_array_of_tables(it.value) {
        dotted_key := build_dotted_key(parent_key, it.key);
        for it.array {
            append(builder, "[[");
            append(builder, dotted_key);
            append(builder, "]]\n");
            print_table_to_builder(builder, it, dotted_key, false);
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
        if maybe_print_naninf_to_builder(builder, value.float_value, *context.print_style.default_format_float) return;
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
    case .FORMAT_INT;  print_integer(builder, value.format_int);
    case .FORMAT_FLOAT;
        format:= value.format_float.value;
        assert(variant_base(format.type).type == .FLOAT);
        f8: float64;
        if      format.type.runtime_size == 4 { f8 = format.value_pointer.(*float32).*; }
        else if format.type.runtime_size == 8 { f8 = format.value_pointer.(*float64).*; }
        else { assert(false, "Unsupported float size %", format.type.runtime_size); }

        if maybe_print_naninf_to_builder(builder, f8, value.format_float) return;
        print_float(builder, value.format_float.*);
    }
}

print_to_builder_escaped :: (builder: *String_Builder, str: string, $is_key: bool) {
    #if is_key { if is_bare_key(str) { append(builder, str); return; } }

    append(builder, "\""); // TODO consider single ' and multiline strings, Note multiline should impact is_inline_table
	for str if it == {
        case "\x08"; append(builder, "\\b");
        case "\t";   append(builder, "\\t");
        case "\n";   append(builder, "\\n");
        case "\x0c"; append(builder, "\\f");
        case "\r";   append(builder, "\\r");
        case "\"";   append(builder, "\\\"");
        case "\\";   append(builder, "\\\\");
        case;
            is_control := it <= 0x1F || it == 0x7F;
            if is_control print_to_builder(builder, "\\u%", FormatInt.{value=it, minimum_digits=4, base=16});
            else          append(builder, it);
    }
    append(builder, "\"");
}

// Remove when stb_print_float or FormatFloat support configuring the nan/inf_label
maybe_print_naninf_to_builder :: (builder: *String_Builder, value: float64, format: *FormatFloat) -> nan_or_inf:bool {
    is_nan, is_inf := is_nan_is_inf(value);
    if !is_nan && !is_inf  return false;
    format_ := format.*;           // Copy format to avoid leaking data onto the context
    format_.value = value;
    ifnan := sprint("%", format_); // Use print to adhere to formatting like width
    to_lower_in_place(ifnan);      // Print uses Inf and NaN instead of inf and nan
    append(builder, ifnan);
    return true;
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

variant_base :: (type: *Type_Info) -> *Type_Info {
    while type.type == .VARIANT {
        type = type.(*Type_Info_Variant).variant_of;
    }
    return type;
}

#scope_file
#import "Basic";
#import "Math";
Reflection :: #import "Reflection";
