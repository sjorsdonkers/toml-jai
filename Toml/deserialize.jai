
deserialize :: (contents: string, $Target: Type) -> Target {
    value := parse(contents);
    return deserialize(value, Target);
}

// NOTE: Allocated objects will have shared ownership by the value and the target
deserialize :: (value: Value, $Target: Type) -> Target {
    target : Target;
    bytes := cast(*u8) *target;
    info :: type_info(Target);
    deserialize(value, bytes, info);
    return target;
}

#scope_file

deserialize :: (toml: Value, slot: *u8, info: *Type_Info, parent_name:string="", name:string="") {
    value_info :: type_info(Value);
    if info == value_info {
        <<cast(*Value) slot = toml;
        return;
    }

    if info.type == { // #complete
    case .INTEGER;
        expect(toml.type, .INT, parent_name, name);
        // TODO support u64, delay parsing till here so we known wheter to parse signed or unsigned / or store u64 as well
        int_info := cast(*Type_Info_Integer)info;
        valid, low, high := range_check_and_store(toml.int_value, int_info, slot);
        if !valid {
            log_error("Value for %.% is out of range. Given % expected min % max %", parent_name, name, toml.int_value, low, high);
            exit(1);
        }
    case .FLOAT;
        expect(toml.type, .FLOAT, parent_name, name);
        if info.runtime_size == 4 {
            <<cast(*float) slot = cast(float) toml.float_value; // TODO not lossless, delay parsing
        } else {
            assert(info.runtime_size == 8);
            <<cast(*float64) slot = toml.float_value;
        }
    case .BOOL;
        expect(toml.type, .BOOL, parent_name, name);
        <<cast(*bool) slot = toml.bool_value;
    case .STRING;
        expect(toml.type, .STRING, parent_name, name);
        // TODO deepcopy to callers allocator
        <<cast(*string) slot = toml.string_value;
    // case .POINTER; // hmm put in permanent memory and point to the value?
    // case .VOID; // Do we want to allow this to be an empty table?
    case .STRUCT;
        expect(toml.type, .TABLE, parent_name, name);
        // handle offset_into_constant_storage
        // handle flags
        // make length safe
        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION {
            log_error("Union are not supported unless they are in a sum-type (struct with enum tag and union where union.members.count == tag.values.count)");
            exit(1);
        }

        sum_type :: (slot: *u8, struct_info: Type_Info_Struct, toml_table: []KeyValue) -> is_sumtype:bool {
            if struct_info.members.count != 2 return false;

            tag_idx :s64=---;
            if struct_info.members[0].type.type == .ENUM && struct_info.members[1].type.type == .STRUCT      then tag_idx = 0;
            else if struct_info.members[0].type.type == .STRUCT && struct_info.members[1].type.type == .ENUM then tag_idx = 1;
            else return false;
            union_idx := 1 - tag_idx;

            tag_info   := cast(*Type_Info_Enum)  struct_info.members[tag_idx].type;
            union_info := cast(*Type_Info_Struct)struct_info.members[union_idx].type;
            if !union_info.textual_flags & .UNION return false;
            // It's a sum-type!

            if union_info.members.count != tag_info.values.count {
                log_error("Sum-type expects each enum variant to match a union variant 1-to-1 got % tags and % union variants for sum-type %", tag_info.values.count, union_info.members.count, struct_info.name);
                exit(1);
            }
            if toml_table.count != 1 {
                log_error("Exactly 1 field expected for sum-type %, got %", struct_info.name, toml_table.count);
                exit(1);
            }
            found, idx := array_find(tag_info.names, toml_table[0].key);
            if !found {
                log_error("String % is not a variant of sum-type %", toml_table[0].key, struct_info.name);
                exit(1);
            }

            tag_slot   := slot + struct_info.members[tag_idx].offset_in_bytes;
            set_enum_value(tag_slot, tag_info, idx);

            union_slot := slot + struct_info.members[union_idx].offset_in_bytes;
            deserialize(toml_table[0].value, union_slot, union_info.members[idx].type, toml_table[0].key, union_info.members[idx].name); // TODO check parent_name
            return true;
        }
        if sum_type(slot, struct_info, toml.table) return;

        for member: struct_info.members {
            found := false;
            for toml.table {
                if it.key == member.name {
                    found = true;
                    member_slot := slot + member.offset_in_bytes;
                    deserialize(it.value, member_slot, member.type, parent_name, member.name); // TODO check parent_name
                    break;
                }
            }
            if !found {
                log_error("Missing field %.%", struct_info.name, member.name);
                exit(1);
            }
        }
    case .ARRAY;
        expect(toml.type, .ARRAY, parent_name, name);
        array_info := cast(*Type_Info_Array) info;
        element_type := array_info.element_type;
        if array_info.array_type == {
            case .FIXED;
                if toml.array.count != array_info.array_count {
                    log_error("Fixed array %.% expected % items, got %", parent_name, name, array_info.array_count, toml.array.count);
                    exit(1);
                }
                for idx: 0..array_info.array_count-1 {
                    array_slot := slot + element_type.runtime_size * idx;
                    deserialize(toml.array[idx], array_slot, element_type, name, "[item]");
                }
            case .VIEW;
                // TODO Same as POINTER
                log_error("Deserialization to type ARRAY VIEW is not supported yet");
                exit(1);
            case .RESIZABLE;
                array := cast(*[..] u8) slot; // We are unable to write the type here (needs to be constant), so just use u8 for now
                array_reserve(array, toml.array.count * element_type.runtime_size);
                for idx: 0..toml.array.count-1 {
                    array_slot := array.data + element_type.runtime_size * idx;
                    deserialize(toml.array[idx], array_slot, element_type, name, "[item]");
                }
                array.count = toml.array.count;
        }
    // case .ANY; // Probably similar to .POINTER
    case .ENUM;
        enum_info := cast(*Type_Info_Enum) info;
        if toml.type == {
        case .STRING;
            found, index := array_find(enum_info.names, toml.string_value);
            if !found {
                log_error("String % is not a variant of enum %", toml.string_value, enum_info.name);
                exit(1);
            }
            set_enum_value(slot, enum_info, enum_info.values[index]);
        case .INT;
            found := array_find(enum_info.values, toml.int_value);
            if !found {
                log_error("Value % is not a variant of enum %", toml.int_value, enum_info.name);
                exit(1);
            }
            set_enum_value(slot, enum_info, toml.int_value);
        case;
            log_error("Wrong type for %.%, expected STRING or INT, got % ", parent_name, name, toml.type);
            exit(1);
        }
    case .VARIANT; // This is a weak or strong alias
        variant_info := cast(*Type_Info_Variant) info;
        deserialize(toml, slot, variant_info.variant_of, parent_name, name);
    case .PROCEDURE;            #through;
    case .OVERLOAD_SET;         #through;
    case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;                 #through;
    case .CODE;                 #through; // Is this possible?
    case;
        log_error("Deserialization to type % is not supported", info.type);
        exit(1);
    }
}

expect :: inline (given: Value.Type, expected: Value.Type, struct_name: string, member_name: string) {
    if given != expected {
        log_error("Wrong type for %.%, expected %, got % ", struct_name, member_name, expected, given);
        exit(1);
    }
}

#load "parser.jai";
#import "Reflection";
