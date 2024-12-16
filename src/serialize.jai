serialize :: (value: Value) -> string {
    builder: String_Builder;
    serialize(*builder, value);
    return builder_to_string(*builder);
}
serialize :: (builder: *String_Builder, value: Value) {
    assert(value.type == .TABLE);
    for value.table {
        print_to_builder_escaped(builder, it.key);
        append(builder, "=");
        serialize(it.value, builder);
        append(builder, "\n");
    }
}

serialize :: (input: $T) -> string {
    builder: String_Builder;
    serialize(*builder, input);
    return builder_to_string(*builder);
}
serialize :: (builder: *String_Builder, input: $T) {
    // assert(value.type == .TABLE);
    // for value.table {
    //     print_to_builder_escaped(builder, it.key);
    //     append(builder, "=");
    //     serialize(it.value, builder);
    //     append(builder, "\n");
    // }
    serialize(*input, type_info(T), builder);
}

#scope_file

serialize :: (slot: *void, info: *Type_Info, builder: *String_Builder) {
    if #complete info.type == {
    case .INTEGER; print_item_to_builder(builder, Any.{info, slot});
    case .FLOAT;
        tmp := tprint("%", Any.{info, slot});
        to_lower_in_place(tmp); // for Inf->inf / NaN->nan
        print_item_to_builder(builder, tmp, false);
    case .BOOL;   print_item_to_builder(builder, Any.{info, slot});
    case .STRING; print_to_builder_escaped(builder, (cast(*string)slot).*);
    case .POINTER; serialize((cast(**void) slot).*, (cast(*Type_Info_Pointer) info).pointer_to, builder); // Should already have been checked for null
    case .VOID; append(builder, "{}");
    case .STRUCT;
        if info == type_info(Value) { serialize(cast(*Value) slot, builder); return; }
        // TODO DATETIME

        flattened := flat_members(xx info);
        replace_uniontag(*flattened, slot);
        append(builder, "{");
        first := true;
        for member: flattened {
            if is_null(slot + member.offset_in_bytes, member.type) continue;
            if !first append(builder, ","); // Here since, never sure if this is last and replacing last written byte to builder is not trivial
            first = false;
            print_to_builder(builder, member.name);
            append(builder, "=");
            serialize(slot + member.offset_in_bytes, member.type, builder);
        }
        append(builder, "}");
    case .ARRAY;
        array_info   := cast(*Type_Info_Array) info;
        array_count  := ifx array_info.array_type == .FIXED then array_info.array_count else (cast(*s64) slot).*;
        array_slot   := ifx array_info.array_type == .FIXED then slot                   else (cast(**void)(slot+8)).*;

        append(builder, "[");
        for idx: 0..array_count-1 {
            element_slot := array_slot + array_info.element_type.runtime_size * idx;
            serialize(element_slot, array_info.element_type, builder);
            append(builder, ",");
        }
        append(builder, "]");
    case .ANY;
        any_value := cast(*Any_Struct) slot;
        serialize(any_value.value_pointer, any_value.type, builder);
    case .ENUM;
        append(builder, #char "\"");
        print_item_to_builder(builder, Any.{info, slot});
        append(builder, #char "\"");
    case .VARIANT;
        variant_info := cast(*Type_Info_Variant) info;
        serialize(slot, variant_info.variant_of, builder);
    case .PROCEDURE;            #through;
    case .OVERLOAD_SET;         #through;
    case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;                 #through;
    case .CODE; exit_with_error("Serialization of type % is not supported", info.type);
    }
}

serialize :: (value: Value, builder: *String_Builder) {
    if #complete value.type == {
    case .BOOL;     print_item_to_builder(builder, value.bool_value);
    case .INT;      print_item_to_builder(builder, value.int_value);
    case .FLOAT;    serialize(*value.float_value, type_info(type_of(value.float_value)), builder);
    case .STRING;   print_to_builder_escaped(builder, value.string_value);
    case .DATETIME; print_item_to_builder(builder, value.datetime, false); // Does not validate datetime string // TODO not item not false?
    case .ARRAY;
        append(builder, "[");
        for value.array {
            serialize(it, builder);
            append(builder, ",");
        }
        append(builder, "]");
    case .TABLE;
        append(builder, "{");
        for value.table {
            print_to_builder_escaped(builder, it.key);
            append(builder, "=");
            serialize(it.value, builder);
            if it_index + 1 != value.table.count then append(builder, ",");
        }
        append(builder, "}");
    }
}

print_to_builder_escaped :: (builder: *String_Builder, str: string) {
    append(builder, "\"");
	for str if it == { // @speed
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
flat_members :: (info:*Type_Info_Struct) -> [..]Type_Info_Struct_Member { // TODO change to for_expansion?
    flat_members :: (flattened:*[..]Type_Info_Struct_Member, info:*Type_Info_Struct, offset_in_bytes: s64) {
        for member: info.members {
            if member.flags & .CONSTANT { continue; }
            if member.flags & .USING && member.type.type == .STRUCT { // NOTE: Enums can be using too
                member_info: *Type_Info_Struct = xx member.type;
                if !(member_info.textual_flags & .UNION) {
                    flat_members(flattened, xx member.type, offset_in_bytes + member.offset_in_bytes);
                    continue;
                }
            }
            array_add(flattened, member);
            peek_pointer(flattened.*).offset_in_bytes += offset_in_bytes;
        }
    }
    flattened: [..]Type_Info_Struct_Member;
    flat_members(*flattened, info, 0);
    return flattened;
}

replace_uniontag :: (flattened:*[..]Type_Info_Struct_Member, slot: *void) {
    index := flattened.count-1;
    while outer:= index >= 0 {
        defer index -= 1;
        member := flattened.*[index];
        // Find union member with @UnionTag note
        if member.type.type != .STRUCT continue;
        member_info := cast(*Type_Info_Struct) member.type;
        if !(member_info.textual_flags & .UNION) continue;
        tag_name: string;
        for note: member.notes if begins_with(note, "UnionTag:") { tag_name = slice(note, 9, note.count-9); break; }
        if !tag_name exit_with_error("Cannot serialize union without knowing which variant is active, @UnionTag:[member_name] is missing");

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
        exit_with_error("Union .%'s tag member `%` cannot be found", member.name, tag_name);
    }
}
is_null :: (slot: *void, info: *Type_Info) -> bool {
    if info.type == .POINTER return slot == null;
    if info.type == .ANY     return (cast(*Any_Struct) slot).value_pointer == null;
    return false;
}

#import "Basic";
