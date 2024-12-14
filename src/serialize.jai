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
    case .POINTER;
        pointer_info := cast(*Type_Info_Pointer) info;
        serialize((cast(**void) slot).*, pointer_info.pointer_to, builder); // Should already have been checked for null
    case .VOID; append(builder, "{}");
    case .STRUCT;
        struct_info := cast(*Type_Info_Struct) info;
        // TODO DATETIME
        append(builder, "{");
        for member: struct_info.members {
            if member.flags & .CONSTANT { continue; }
            // TODO using and union
            // TODO null pointers / null any
            print_to_builder(builder, member.name);
            append(builder, "=");
            serialize(slot + member.offset_in_bytes, member.type, builder);
            // if it_index + 1 != value.table.count then // // todo determine when last
            append(builder, ",");
        }
        append(builder, "}");
    case .ARRAY;
        array_info := cast(*Type_Info_Array) info;
        element_info := array_info.element_type;
        array_slot :=  slot;
        array_count := array_info.array_count;
        if #complete array_info.array_type == {
        case .FIXED; // nothing
        case .VIEW; #through;
        case .RESIZABLE;
            array := cast(*[] u8) slot; // u8 for no particular reason
            array_count = array.count; // (cast(*s64) slot).*
            array_slot = array.data; // (cast(**void)(slot+8)).*
        }

        append(builder, "[");
        for idx: 0..array_count-1 {
            element_slot := array_slot + element_info.runtime_size * idx;
            serialize(element_slot, element_info, builder);
            append(builder, ",");
        }
        append(builder, "]");
    case .ANY;
        any_value := cast(*Any_Struct) slot;
        serialize(any_value.value_pointer, any_value.type, builder);
    case .ENUM;
        append(builder, #char "\"");
        print_item_to_builder(builder, Any.{info, slot}); // TODO check
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
    case .BOOL; print_item_to_builder(builder, value.bool_value);
    case .INT;  print_item_to_builder(builder, value.int_value);
    case .FLOAT;
        tmp := tprint("%", value.float_value);
        to_lower_in_place(tmp); // for Inf->inf / NaN->nan
        print_item_to_builder(builder, tmp, false);
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

#import "Basic";
