serialize :: (input: $T) -> ok:=false, toml:string="" {
    a := scoped_pool();
    ok, value := parse(*input, type_info(T),, a); if !ok return;
    builder: String_Builder;
    serialize(*builder, value,, a);
    return true, builder_to_string(*builder);
}

serialize :: (value: Value) -> ok:=false, toml:string="" {
    builder: String_Builder;
    serialize(*builder, value,, scoped_pool());
    return true, builder_to_string(*builder);
}

#scope_module

// Note: Does not deep copy
parse :: (slot: *void, info: *Type_Info) -> ok:=false, toml:Value=.{} {
    if #complete info.type == {
    case .INTEGER;
        ok, value := get_integer_value(slot, xx info); if !ok return;
        return true, .{type=.INT, int_value=value};
    case .FLOAT;
        if      info.runtime_size == 4 { return true, .{type=.FLOAT, float_value=cast(*float32, slot).*}; }
        else if info.runtime_size == 8 { return true, .{type=.FLOAT, float_value=cast(*float64, slot).*}; }
        else { assert(false, "Unsupported float size %", info.runtime_size); }
    case .BOOL;   return true, .{type=.BOOL, bool_value=cast(*bool, slot).*};
    case .STRING; return true, .{type=.STRING, string_value=cast(*string, slot).*}; // No copy!
    case .POINTER;
        assert(cast(**void, slot) != null, "Implementation error: null pointers should be filtered out");
        ok, value := parse(cast(**void, slot).*, cast(*Type_Info_Pointer, info).pointer_to);
        return ok, value;
    case .VOID;  return true, .{};
    case .STRUCT;
        if info == {
        case type_info(Value);          return true, cast(*Value, slot).*; // No copy!
        case type_info(Chrono);         return true, .{type=.DATETIME, datetime=cast(*Chrono, slot).*};
        case type_info(Time);           return true, .{type=.DATETIME, datetime=.{type=.LOCAL_TIME,      time=           cast(*Time, slot).*}};
        case type_info(Date);           return true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATE,      date=           cast(*Date, slot).*}};
        case type_info(DateTime);       return true, .{type=.DATETIME, datetime=.{type=.LOCAL_DATETIME,  datetime=       cast(*DateTime, slot).*}};
        case type_info(DateTimeOffset); return true, .{type=.DATETIME, datetime=.{type=.OFFSET_DATETIME, datetime_offset=cast(*DateTimeOffset, slot).*}};
        }
        flattened := flat_nonnull_members(slot, xx info);
        replace_uniontag(slot, *flattened);

        table: [..]KeyValue;
        array_reserve(*table, flattened.count);
        for member: flattened {
            ok, value := parse(slot + member.offset_in_bytes, member.type); if !ok return;
            kv := KeyValue.{key=member.name, value=value};
            array_add(*table, kv);
        }
        return true, .{type=.TABLE, table=table};
    case .ARRAY;
        array_info :*Type_Info_Array= xx info;
        array_count  := ifx array_info.array_type == .FIXED then array_info.array_count else cast(*s64,   slot).*;
        array_slot   := ifx array_info.array_type == .FIXED then slot                   else cast(**void, slot+8).*;

        array: [..]Value;
        array_reserve(*array, array_count);
        for idx: 0..array_count-1 {
            element_slot := array_slot + array_info.element_type.runtime_size * idx;
            if is_null(element_slot, array_info.element_type) return_with_error("Null pointer in array detected which is not supported");
            ok, v := parse(element_slot, array_info.element_type); if !ok return;
            array_add(*array, v);
        }
        return true, .{type=.ARRAY, array=array};
    case .ANY;
        any_value :*Any_Struct= xx slot;
        assert(any_value.value_pointer != null, "Implementation error: null pointers should be filtered out");
        ok, value := parse(any_value.value_pointer, any_value.type);
        return ok, value;
    case .ENUM;
        enum_info :*Type_Info_Enum= xx info;
        for enum_info.values  if it == get_enum_value(slot, enum_info) {
            return true, .{type=.STRING, string_value=enum_info.names[it_index]};
        }
        assert(false, "Enum value % not found in enum %", get_enum_value(slot, enum_info), enum_info.name);
    case .VARIANT;
        ok, value := parse(slot, cast(*Type_Info_Variant, info).variant_of);
        return ok, value;
    case .PROCEDURE;            #through;
    case .OVERLOAD_SET;         #through;
    case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;                 #through;
    case .CODE;
    }
    return_with_error("Parsing of type % is not supported", info.type);
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
        has_inline := it.table.count == 0; // Do not start a [table.header] if there are no inline values
        for it.table if it.type != .TABLE || !is_table_header(it.value) { has_inline = true; break; }
        if has_inline {
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
    case .BOOL;     print_item_to_builder(builder, value.bool_value);
    case .INT;      print_item_to_builder(builder, value.int_value);
    case .FLOAT;
        if isnan(value.float_value) {
            if (cast(*u64, *value.float_value).* & 0x8000_0000_0000_0000) { append(builder, "-"); }
            append(builder, "nan");
        } else if isinf(value.float_value) {
            if (cast(*u64, *value.float_value).* & 0x8000_0000_0000_0000) { append(builder, "-"); }
            append(builder, "inf");
        } else {
            print_item_to_builder(builder, value.float_value);
        }
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

// Collect all variables members and flattens using structs incl. unions, keeps original using members as well, needed for uniontag
flat_nonnull_members :: (slot: *void, info:*Type_Info_Struct) -> [..]Type_Info_Struct_Member {
    flat_nonnull_members :: (slot: *void, flattened:*[..]Type_Info_Struct_Member, info:*Type_Info_Struct, offset_in_bytes: s64) {
        for member: info.members {
            if member.flags & .CONSTANT { continue; }
            if member.flags & .USING && member.type.type == .STRUCT { // NOTE: Enums can be using too
                member_info: *Type_Info_Struct = xx member.type;
                if !(member_info.textual_flags & .UNION) {
                    flat_nonnull_members(slot, flattened, xx member.type, offset_in_bytes + member.offset_in_bytes);
                    continue;
                }
            }
            if is_null(slot + offset_in_bytes + member.offset_in_bytes, member.type) continue;
            array_add(flattened, member);
            peek_pointer(flattened.*).offset_in_bytes += offset_in_bytes;
        }
    }
    flattened: [..]Type_Info_Struct_Member;
    flat_nonnull_members(slot, *flattened, info, 0);
    return flattened;
}

replace_uniontag :: (slot: *void, flattened:*[..]Type_Info_Struct_Member) {
    index := flattened.count-1;
    while outer:= index >= 0 {
        defer index -= 1;
        member := flattened.*[index];
        // Find union member with @UnionTag note
        if member.type.type != .STRUCT continue;
        member_info := cast(*Type_Info_Struct, member.type);
        if !(member_info.textual_flags & .UNION) continue;
        tag_name: string;
        for note: member.notes if begins_with(note, "UnionTag:") { tag_name = slice(note, 9, note.count-9); break; }
        assert(tag_name!="", "Cannot serialize union without knowing which variant is active, @UnionTag:[member_name] is missing");

        // Remove it's tag member, replace union by its active variant
        for flattened.* if it.name == tag_name { // find instead of loop
            assert(it.type.type == .ENUM);
            tag_idx := get_enum_value(slot + it.offset_in_bytes, xx it.type);
            current_variant := member_info.members[tag_idx];
            current_variant.offset_in_bytes += member.offset_in_bytes;
            flattened.*[index] = current_variant;

            array_ordered_remove_by_index(flattened, it_index);
            if it_index < index { index -= 1; }
            continue outer;
        }
        assert(false, "Union .%'s tag member `%` cannot be found", member.name, tag_name);
    }
}

is_null :: (slot: *void, info: *Type_Info) -> bool {
    if info.type == .POINTER return cast(**void, slot).* == null;
    if info.type == .ANY     return cast(*Any_Struct, slot).value_pointer == null;
    return false;
}

// true if it would otherwise introduce additional braces or brackets, so no in-line tables or arrays in in-line tables,
// additionally also not: a = {b.c = 1, b.d = 2, e = 3} as it is equivalent to: a = { b= {c = 1, d = 2}, e = 3}
is_table_header :: (value: Value) -> bool {
    is_single_value :: (table: []KeyValue) -> bool {
        if table.count != 1 return false;
        if table[0].type == {
        case .TABLE;
            return is_single_value(table[0].table);
        case .ARRAY; return false;
        case; return true;
        }
    }
    if value.type != .TABLE return false;
    for value.table if it.type == {
    case .TABLE;
        if !is_single_value(it.table) return true;
    case .ARRAY; return true;
    }
    return value.table.count == 0;
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
