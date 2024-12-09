
deserialize :: (contents: string, $Target: Type) -> Target {
    #if Target == Value return parse(contents); // Prevents unnecessarily copying
    value := parse(contents,, allocator=temp);
    return deserialize(value, Target);
}

deserialize :: (value: Value, $Target: Type) -> Target {
    info :: type_info(Target);
    target :Target;
    reinitialize_all_unions(*target, info); // TODO remove when union init is normal Jai behavior (not the case in: Version: beta 0.1.096)
    deserialize(value, *target, info);
    return target;
}

#scope_file

// slot is already initialized memory
// Currently all fields are optional. TODO check TomlOptional Note and require_all true/false
deserialize :: (toml: Value, slot: *void, info: *Type_Info, parent_name:string="", name:string="") {
    value_info :: type_info(Value);
    if info == value_info { // If encounter we Toml.Value at any point just copy it
        <<cast(*Value) slot = copy(toml);
        return;
    }

    if #complete info.type == {
    case .INTEGER;
        expect(toml.type, .INT, parent_name, name);
        valid, low, high := range_check_and_store(toml.int_value, cast(*Type_Info_Integer)info, slot);
        if !valid { exit_with_error("Value for %.% is out of range. Given % expected min % max %", parent_name, name, toml.int_value, low, high); }
    case .FLOAT;
        expect(toml.type, .FLOAT, parent_name, name);
        if      info.runtime_size == 4 { <<cast(*float)   slot = cast(float) toml.float_value; }
        else if info.runtime_size == 8 { <<cast(*float64) slot = toml.float_value; }
        else { exit_with_error("Unsupported float size %", info.runtime_size); }
    case .BOOL;
        expect(toml.type, .BOOL, parent_name, name);
        <<cast(*bool) slot = toml.bool_value;
    case .STRING;
        if toml.type != .DATETIME expect(toml.type, .STRING, parent_name, name);
        <<cast(*string) slot = copy_string(toml.string_value); // Note: datetime is string as well so same memory layout
    case .POINTER;
        pointer_info := cast(*Type_Info_Pointer) info;
        memory := alloc(pointer_info.pointer_to.runtime_size);
        initialize_memory(memory, pointer_info.pointer_to);
        <<cast(**void)slot = memory;
        deserialize(toml, memory, pointer_info.pointer_to, parent_name, name);
    case .VOID;
        if toml.type == {
        case .STRING; if toml.string_value != "void" { exit_with_error("Expected 'void' for %.%, got %", parent_name, name, toml.string_value);     }
        case .TABLE ; if toml.table.count  != 0      { exit_with_error("Expected empty table for %.%, got %", parent_name, name, toml.table.count); }
        case; exit_with_error("Expected 'void' or empty table for %.%, got %", parent_name, name, toml.type);
        }
    case .STRUCT;
        expect(toml.type, .TABLE, parent_name, name);
        if toml.table.count == 0 { return; } // Use defaults

        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION { exit_with_error("Union are not supported unless they are in a sum-type (struct with enum tag and union where union.members.count == tag.values.count)"); }

        struct_members := collect_members(struct_info);
        if deserialize_sumtype(toml, slot, struct_members, struct_info.name) return;

        for member: struct_members { for toml.table { if it.key == member.name {
            member_slot := slot + member.offset_in_bytes;
            deserialize(it.value, member_slot, member.type, parent_name, member.name);
            break;
        } } }
    case .ARRAY;
        expect(toml.type, .ARRAY, parent_name, name);
        array_info := cast(*Type_Info_Array) info;
        element_type := array_info.element_type;

        fill_array :: (toml_array: []Value, slot: *void, item_info: *Type_Info, parent_name:string) {
            for idx: 0..toml_array.count-1 {
                item_slot := slot + item_info.runtime_size * idx;
                deserialize(toml_array[idx], item_slot, item_info, parent_name, "[item]");
            }
        }
        if #complete array_info.array_type == {
            case .FIXED;
                if toml.array.count != array_info.array_count { exit_with_error("Fixed array %.% expected % items, got %", parent_name, name, array_info.array_count, toml.array.count); }
                fill_array(toml.array, slot, element_type, name); // NOTE .FIXED is inside the struct so already initialized
            case .VIEW;
                array := cast(*[] u8) slot;
                array.data = alloc(toml.array.count * element_type.runtime_size);
                array.count = toml.array.count;
                initialize_memory(array.data, element_type, array.count);
                fill_array(toml.array, array.data, element_type, name);
            case .RESIZABLE;
                array := cast(*[..] u8) slot;
                array_reserve(array, toml.array.count * element_type.runtime_size);
                array.count = toml.array.count;
                initialize_memory(array.data, element_type, array.count);
                fill_array(toml.array, array.data, element_type, name);
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
            case .DATETIME; return true, type_info([]type_of(Value.datetime));
            }
            return false, null;
        }

        if #complete toml.type == {
        case .BOOL;   any_value.type = type_info(type_of(Value.bool_value));
        case .INT;    any_value.type = type_info(type_of(Value.int_value));
        case .FLOAT;  any_value.type = type_info(type_of(Value.float_value));
        case .STRING; any_value.type = type_info(type_of(Value.string_value));
        case .DATETIME; any_value.type = type_info(type_of(Value.datetime));
        case .ARRAY;
            is_same, array_type := homogeneous_array_info(toml.array);
            any_value.type = ifx is_same then array_type else type_info(type_of(Value.array));
        case .TABLE;  any_value.type = type_info(type_of(Value.table));
        }
        any_value.value_pointer = alloc(any_value.type.runtime_size);
        initialize_memory(any_value.value_pointer, any_value.type);
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
        case; exit_with_error("Wrong type for %.%, expected STRING or INT, got % ", parent_name, name, toml.type);
        }
    case .VARIANT;
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

deserialize_sumtype :: (toml: Value, slot: *void, struct_members: []Type_Info_Struct_Member, struct_name:string) -> is_sumtype:bool {
    if struct_members.count != 2 return false;

    tag_idx :s64=---;
    if struct_members[0].type.type == .ENUM && struct_members[1].type.type == .STRUCT      then tag_idx = 0;
    else if struct_members[0].type.type == .STRUCT && struct_members[1].type.type == .ENUM then tag_idx = 1;
    else return false;
    union_idx := 1 - tag_idx;

    tag_info   := cast(*Type_Info_Enum)  struct_members[tag_idx].type;
    union_info := cast(*Type_Info_Struct)struct_members[union_idx].type;
    if !union_info.textual_flags & .UNION return false;
    if union_info.members.count != tag_info.values.count return false;
    // It's a sum-type!

    tag_slot   := slot + struct_members[tag_idx].offset_in_bytes;
    union_slot := slot + struct_members[union_idx].offset_in_bytes;
    union_members := collect_union_members(union_info);

    if toml.table.count != 1 { exit_with_error("Exactly 1 field expected for sum-type %, got %", struct_name, toml.table.count); }
    found, idx := array_find(tag_info.names, toml.table[0].key);
    if !found { exit_with_error("String % is not a variant of sum-type % %", toml.table[0].key, struct_name, tag_info.names); }

    set_enum_value(tag_slot, tag_info, idx);
    deserialize(toml.table[0].value, union_slot, union_members[idx].type, tag_info.names[idx], union_info.members[idx].name);
    return true;
}

// Collect all variables members and flattens non-union using structs
collect_members :: (struct_info:*Type_Info_Struct) -> [..]Type_Info_Struct_Member {
    collect_members :: (struct_members:*[..]Type_Info_Struct_Member, struct_info:*Type_Info_Struct, offset_in_bytes: s64) {
        for member: struct_info.members {
            if member.flags & .CONSTANT { continue; }
            if member.flags & .USING {
                if (member.type.type == .STRUCT) { // NOTE: Enums can be using too, but they don't have members to flatten
                    member_struct_info:= cast(*Type_Info_Struct) member.type;
                    if !(member_struct_info.textual_flags & .UNION) { // Don't flatten unions
                        collect_members(struct_members, member_struct_info, offset_in_bytes + member.offset_in_bytes);
                        continue; // Don't add the using itself
                    }
                }
            }

            array_add(struct_members, member);
            (<<struct_members)[struct_members.count-1].offset_in_bytes += offset_in_bytes;
        }
    }
    struct_members: [..]Type_Info_Struct_Member;
    collect_members(*struct_members, struct_info, 0);
    return struct_members;
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

// Initializes union members to their first variant at every level within the given memory/info
reinitialize_all_unions :: (memory: *void, info: *Type_Info) {
    if info.type == {
    case .STRUCT;
        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION {
            if struct_info.members.count <= 0 { return; }
            initialize_memory(memory, struct_info.members[0].type);
            return;
        }

        for member: struct_info.members {
            if member.flags & .CONSTANT { continue; }
            reinitialize_all_unions(memory + member.offset_in_bytes, member.type);
        }
    case .ARRAY;
        array_info := cast(*Type_Info_Array) info;
        if array_info.array_type == .FIXED {
            for 0..array_info.array_count-1 {
                reinitialize_all_unions(memory + array_info.element_type.runtime_size * it, array_info.element_type);
            }
        }
    case .VARIANT;
        variant_info := cast(*Type_Info_Variant) info;
        reinitialize_all_unions(memory, variant_info.variant_of);
    }
}

initialize_memory :: (memory: *void, info: *Type_Info, count:s64=1) {
    if count <= 0 || info.runtime_size <= 0 return;
    total_size := count * info.runtime_size;

    if info.type == {
    case .STRUCT;
        struct_info := cast(*Type_Info_Struct) info;
        if struct_info.textual_flags & .UNION {
            assert(struct_info.members.count > 0); // Note if members.count where 0 runtime_size would be 0, so there should at least be 1 member
            initialize_memory(memory, struct_info.members[0].type, count); // TODO Hack to deal with inconsistent union initialization
            return;
        }
        if struct_info.initializer {
            current := memory;
            for 0..count-1 {
                struct_info.initializer(current);
                reinitialize_all_unions(current, struct_info); // Same hack
                current += struct_info.runtime_size;
            }
            return;
        }
    case .ARRAY;
        array_info := cast(*Type_Info_Array) info;
        if array_info.array_type == .FIXED {
            initialize_memory(memory, array_info.element_type, array_info.array_count);
            return;
        }
    case .VARIANT;
        variant_info := cast(*Type_Info_Variant) info;
        initialize_memory(memory, variant_info.variant_of);
        return;
    }
    memset(memory, 0, total_size);
}

#load "parser.jai";
#import "Reflection";
