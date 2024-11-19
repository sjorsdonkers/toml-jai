
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
    case .VOID;
        expect(toml.type, .TABLE, parent_name, name);
        if toml.table.count != 0 {
            log_error("Expected empty table for %.%, got %", parent_name, name, toml.table.count);
            exit(1);
        }
    case .STRUCT;
        expect(toml.type, .TABLE, parent_name, name);
        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION {
            log_error("Union are not supported unless they are in a sum-type (struct with enum tag and union where union.members.count == tag.values.count)");
            exit(1);
        }

        struct_members := collect_members(struct_info);
        if deserialize_sumtype(toml, slot, struct_members, struct_info.name) return;

        for member: struct_members {
            found := false;
            for toml.table {
                if it.key == member.name {
                    found = true;
                    member_slot := slot + member.offset_in_bytes;
                    if deserialize_option(it.value, member_slot, member.type) break; // Some does expect its tag
                    deserialize(it.value, member_slot, member.type, parent_name, member.name); // TODO check parent_name
                    break;
                }
            }
            if !found && member.type.type != .VOID {
                member_slot := slot + member.offset_in_bytes;
                empty_table := Value.{type=.TABLE, array=resizable(Value.[])}; // TODO
                if deserialize_option(empty_table, member_slot, member.type) continue; // None does not expect its tag or value

                log_error("Missing field %.%", struct_info.name, member.name);
                exit(1);
            }
        }
    case .ARRAY; // TODO check array of options
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

deserialize_sumtype :: (toml: Value, slot: *u8, struct_members: []Type_Info_Struct_Member, struct_name:string) -> is_sumtype:bool {
    if struct_members.count != 2 return false;

    tag_idx :s64=---;
    if struct_members[0].type.type == .ENUM && struct_members[1].type.type == .STRUCT      then tag_idx = 0;
    else if struct_members[0].type.type == .STRUCT && struct_members[1].type.type == .ENUM then tag_idx = 1;
    else return false;
    union_idx := 1 - tag_idx;

    tag_info   := cast(*Type_Info_Enum)  struct_members[tag_idx].type;
    union_info := cast(*Type_Info_Struct)struct_members[union_idx].type;
    if !union_info.textual_flags & .UNION return false;
    if union_info.members.count != tag_info.values.count {
        log_error("Sum-type expects each enum variant to match a union variant 1-to-1 got % tags and % union variants for sum-type %", tag_info.values.count, union_info.members.count, struct_name);
        exit(1);
    }
    // It's a sum-type!

    tag_slot   := slot + struct_members[tag_idx].offset_in_bytes;
    union_slot := slot + struct_members[union_idx].offset_in_bytes;
    union_members := collect_union_members(union_info);

    // Handle empty table as void/none NOTE: if member was missing from toml an empty table is inserted
    if toml.type == .TABLE && toml.table.count == 0 {
        found, void_idx := find_void_index(union_members);
        if !found {
            log_error("Sum-type % does not have an optional (void) variant", struct_name); // TODO name
            exit(1);
        }
        set_enum_value(tag_slot, tag_info, void_idx);
        return true; // void does not have bytes to set
    }
    // Special case for Option type defined as a sum-type with 2 members 1 being void.
    // The TOML is not expected to contain the Option tags some/none.
    if union_members.count == 2 { // Search void also if union_members.count == 2 handle as optional which does not introduce new names for some / none
        found, void_idx := find_void_index(union_members);
        if found {
            some_idx : = 1 - void_idx;
            set_enum_value(tag_slot, tag_info, some_idx);
            deserialize(toml, union_slot, union_members[some_idx].type, tag_info.names[some_idx], union_info.members[some_idx].name); // TODO check parent_name
            return true;
        }
    }
    if toml.type != .TABLE {
        log_error("A value is provided without naming the variant first for sum-type %", struct_name); // TODO name
        exit(1);
    }
    if toml.table.count != 1 {
        log_error("Exactly 1 field expected for sum-type %, got %", struct_name, toml.table.count);
        exit(1);
    }
    found, idx := array_find(tag_info.names, toml.table[0].key);
    if !found {
        log_error("String % is not a variant of sum-type % %", toml.table[0].key, struct_name, tag_info.names);
        exit(1);
    }

    set_enum_value(tag_slot, tag_info, idx);
    deserialize(toml.table[0].value, union_slot, union_members[idx].type, tag_info.names[idx], union_info.members[idx].name); // TODO check parent_name
    return true;
}
deserialize_option :: (toml: Value, member_slot: *u8, member_info: *Type_Info) -> is_sum_type:bool {
    if member_info.type == .STRUCT {
        member_struct_info := cast(*Type_Info_Struct) member_info;
        member_struct_members := collect_members(member_struct_info);
        return deserialize_sumtype(toml, member_slot, member_struct_members, member_struct_info.name);
    }
    return false;
}

// Collect all variables members and flattens non-union using structs
collect_members :: (struct_info:*Type_Info_Struct) -> [..]Type_Info_Struct_Member {
    struct_members: [..]Type_Info_Struct_Member;
    collect_members(*struct_members, struct_info, 0);
    return struct_members;
}
collect_members :: (struct_members:*[..]Type_Info_Struct_Member, struct_info:*Type_Info_Struct, offset_in_bytes: s64) {
    for member: struct_info.members {
        if member.flags & .CONSTANT { continue; }
        if member.flags & .USING {
            if (member.type.type == .STRUCT) { // NOTE: Enums can be using too, but they don't have members to flatten
                sub_member:= cast(*Type_Info_Struct) member.type;
                if !(sub_member.textual_flags & .UNION) { // Don't flatten unions
                    collect_members(struct_members, sub_member, offset_in_bytes + member.offset_in_bytes);
                    continue; // Don't add the using itself
                }
            }
        }

        array_add(struct_members, member);
        (<<struct_members)[struct_members.count-1].offset_in_bytes += offset_in_bytes;
    }
}

// Flatten variants of the union, only needed for Sum_Type support
collect_union_members :: (union_info:*Type_Info_Struct) -> [..]Type_Info_Struct_Member {
    union_members: [..]Type_Info_Struct_Member;
    array_reserve(*union_members, union_info.members.count);
    for member: union_info.members {
        if member.type.type == .STRUCT {  // Check if type is a wrapped Sum_Type variant
            variant_info := cast(*Type_Info_Struct) member.type;
            if variant_info.members.count == 1 && variant_info.members[0].name == "value" {
                array_add(*union_members, variant_info.members[0]);
                continue;
            }
        }
        array_add(*union_members, member);
    }
    return union_members;
}

// Find the index of the void member in the union, returns false if there are multiple voids
find_void_index ::(union_members: []Type_Info_Struct_Member)-> found:bool, index:s64 {
    index := -1;
    for union_members {  if it.type.type == .VOID {
        if index != -1 { return false, -1; } // More than one void
        index = it_index;
    }}
    return index != -1, index;
}

#load "parser.jai";
#import "Reflection";
