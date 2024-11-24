
deserialize :: (contents: string, $Target: Type) -> Target {
    value := parse(contents);
    return deserialize(value, Target);
}

// NOTE: Allocated value objects will have shared ownership by the value and the target
// Reference objects (pointers, array views, any) will be reallocated(?)
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
    if info == value_info { // If encounter a Toml.Value at any point just copy it
        <<cast(*Value) slot = toml;
        return;
    }

    if #complete info.type == {
    case .INTEGER;
        expect(toml.type, .INT, parent_name, name);
        // TODO support u64, delay parsing till here so we known wheter to parse signed or unsigned / or store u64 as well
        int_info := cast(*Type_Info_Integer)info;
        valid, low, high := range_check_and_store(toml.int_value, int_info, slot);
        if !valid { exit_with_error("Value for %.% is out of range. Given % expected min % max %", parent_name, name, toml.int_value, low, high); }
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
    case .POINTER;
        pointer_info := cast(*Type_Info_Pointer) info;
        memory := alloc(pointer_info.pointer_to.runtime_size);
        <<cast(**u8)slot = memory;
        deserialize(toml, memory, pointer_info.pointer_to, parent_name, name);
    case .VOID;
        if toml.type == {
        case .STRING; if toml.string_value != "void" { exit_with_error("Expected 'void' for %.%, got %", parent_name, name, toml.string_value);     }
        case .TABLE ; if toml.table.count  != 0      { exit_with_error("Expected empty table for %.%, got %", parent_name, name, toml.table.count); }
        case; exit_with_error("Expected 'void' or empty table for %.%, got %", parent_name, name, toml.type);
        }
    case .STRUCT;
        if deserialize_option(toml, slot, info) return; // For Option.Some values we don't expect the TABLE of the Option itself
        expect(toml.type, .TABLE, parent_name, name);
        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION { exit_with_error("Union are not supported unless they are in a sum-type (struct with enum tag and union where union.members.count == tag.values.count)"); }

        struct_members := collect_members(struct_info);
        if deserialize_sumtype(toml, slot, struct_members, struct_info.name) return;

        // We could initialize all members and let it be OK if some are not in the TOML
        // However TOML text files are not compiled and much more prone to typos.
        // As such for now we require the user to be explicit about which struct members are optional with Option.
        // Also, I do not known how to detect which members have an explict default value and which do not.
        // if struct_info.initializer then struct_info.initializer(memory); else just memset zeros

        for member: struct_members {
            found := false;
            for toml.table {
                if it.key == member.name {
                    found = true;
                    member_slot := slot + member.offset_in_bytes;
                    deserialize(it.value, member_slot, member.type, parent_name, member.name);
                    break;
                }
            }
            if !found && member.type.type != .VOID {
                member_slot := slot + member.offset_in_bytes;
                empty_table := Value.{type=.TABLE, array=resizable(Value.[])};
                if deserialize_option(empty_table, member_slot, member.type) continue; // None does not expect its tag or value

                exit_with_error("Missing field %.%", struct_info.name, member.name);
            }
        }
    case .ARRAY;
        expect(toml.type, .ARRAY, parent_name, name);
        array_info := cast(*Type_Info_Array) info;
        element_type := array_info.element_type;

        fill_array :: (toml_array: []Value, slot: *u8, item_info: *Type_Info, parent_name:string) {
            for idx: 0..toml_array.count-1 {
                item_slot := slot + item_info.runtime_size * idx;
                deserialize(toml_array[idx], item_slot, item_info, parent_name, "[item]");
            }
        }

        if array_info.array_type == {
            case .FIXED;
                if toml.array.count != array_info.array_count { exit_with_error("Fixed array %.% expected % items, got %", parent_name, name, array_info.array_count, toml.array.count); }
                fill_array(toml.array, slot, element_type, name);
            case .VIEW;
                memory := alloc(toml.array.count * element_type.runtime_size);
                fill_array(toml.array, memory, element_type, name);
                array := cast(*[..] u8) slot;
                array.data = memory;
                array.count = toml.array.count;
            case .RESIZABLE;
                array := cast(*[..] u8) slot; // We are unable to write the type here (needs to be constant), so just use u8 for now
                array_reserve(array, toml.array.count * element_type.runtime_size);
                fill_array(toml.array, array.data, element_type, name);
                array.count = toml.array.count;
        }
    case .ANY;
        any_value := cast(*Any_Struct) slot;

        homogeneous_array_info :: (array: []Value) -> is_same_type:bool, *Type_Info {
            if array.count == 0 { return false, null; }
            first_type := array[0].type;
            if first_type == .ARRAY || first_type == .TABLE { return false, null; } // Not going down multiple levels
            for array { if it.type != first_type { return false, null; }}
            if first_type == {
            case .BOOL;   return true, type_info([]type_of(Value.bool_value));
            case .INT;    return true, type_info([]type_of(Value.int_value));
            case .FLOAT;  return true, type_info([]type_of(Value.float_value));
            case .STRING; return true, type_info([]type_of(Value.string_value));
            }
            return false, null;
        }

        if #complete toml.type == {
        case .BOOL;   any_value.type = type_info(type_of(Value.bool_value));
        case .INT;    any_value.type = type_info(type_of(Value.int_value));
        case .FLOAT;  any_value.type = type_info(type_of(Value.float_value));
        case .STRING; any_value.type = type_info(type_of(Value.string_value));
        case .ARRAY;
            is_same, array_type := homogeneous_array_info(toml.array);
            any_value.type = ifx is_same then array_type else type_info(type_of(Value.array));
        case .TABLE;  any_value.type = type_info(type_of(Value.table));
        }
        any_value.value_pointer = alloc(any_value.type.runtime_size);
        deserialize(toml, any_value.value_pointer, any_value.type, parent_name, name);
    case .ENUM;
        enum_info := cast(*Type_Info_Enum) info;
        if toml.type == {
        case .STRING;
            found, index := array_find(enum_info.names, toml.string_value);
            if !found { exit_with_error("String % is not a variant of enum %", toml.string_value, enum_info.name); }
            set_enum_value(slot, enum_info, enum_info.values[index]);
        case .INT;
            found := array_find(enum_info.values, toml.int_value);
            if !found { exit_with_error("Value % is not a variant of enum %", toml.int_value, enum_info.name); }
            set_enum_value(slot, enum_info, toml.int_value);
        case;
            exit_with_error("Wrong type for %.%, expected STRING or INT, got % ", parent_name, name, toml.type);
        }
    case .VARIANT; // This is a weak or strong alias
        variant_info := cast(*Type_Info_Variant) info;
        deserialize(toml, slot, variant_info.variant_of, parent_name, name);
    case .PROCEDURE;            #through;
    case .OVERLOAD_SET;         #through;
    case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;                 #through;
    case .CODE;                 #through;
    case; exit_with_error("Deserialization to type % is not supported", info.type);
    }
}

expect :: inline (given: Value.Type, expected: Value.Type, struct_name: string, member_name: string) {
    if given != expected { exit_with_error("Wrong type for %.%, expected %, got % ", struct_name, member_name, expected, given); }
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
    if union_info.members.count != tag_info.values.count { exit_with_error("Sum-type expects each enum variant to match a union variant 1-to-1 got % tags and % union variants for sum-type %", tag_info.values.count, union_info.members.count, struct_name); }
    // It's a sum-type!

    tag_slot   := slot + struct_members[tag_idx].offset_in_bytes;
    union_slot := slot + struct_members[union_idx].offset_in_bytes;
    union_members := collect_union_members(union_info);

    // Handle empty table as void/none NOTE: if member was missing from toml an empty table is inserted
    if toml.type == .TABLE && toml.table.count == 0 {
        found, void_idx := find_void_index(union_members);
        if !found { exit_with_error("Sum-type % does not have an optional (void) variant", struct_name); }
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
            deserialize(toml, union_slot, union_members[some_idx].type, tag_info.names[some_idx], union_info.members[some_idx].name);
            return true;
        }
    }
    if toml.type != .TABLE { exit_with_error("A value is provided without naming the variant first for sum-type %", struct_name); }
    if toml.table.count != 1 { exit_with_error("Exactly 1 field expected for sum-type %, got %", struct_name, toml.table.count); }
    found, idx := array_find(tag_info.names, toml.table[0].key);
    if !found { exit_with_error("String % is not a variant of sum-type % %", toml.table[0].key, struct_name, tag_info.names); }

    set_enum_value(tag_slot, tag_info, idx);
    deserialize(toml.table[0].value, union_slot, union_members[idx].type, tag_info.names[idx], union_info.members[idx].name);
    return true;
}
deserialize_option :: (toml: Value, member_slot: *u8, member_info: *Type_Info) -> is_sum_type:bool { // TODO sep. is sum deser some deser none
    if member_info.type == .STRUCT {
        member_struct_info := cast(*Type_Info_Struct) member_info;
        member_struct_members := collect_members(member_struct_info); // @perf cache this and is_sumtype/is_option
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

exit_with_error :: (format: string, arguments: .. Any) {
    log_error(format, ..arguments);
    exit(1);
}

#load "parser.jai";
#import "Reflection";
#import "Compiler";
