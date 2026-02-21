deserialize :: inline (contents: string, $Target: Type) -> ok:=false, value:Target=.{} #deprecated "Renamed string_to_type" { ok, value := string_to_type(contents, Target); return ok, value; }
string_to_type :: (contents: string, $Target: Type) -> ok:=false, value:Target=.{} {
    auto_release_temp_maybe();

    ok, value := string_to_value_shared_memory(contents,, temp); if !ok return;
    ok=, target := value_to_type(value, Target);
    return ok, target;
}

value_to_type :: (toml: Value, $Target: Type) -> ok:=false, value:Target {
    auto_release_temp_maybe();

    info :: type_info(Target);
    target: Target;
    root_name := ifx info.type == .STRUCT then info.(*Type_Info_Struct).name else "root";
    ok := context.toml.custom_value_to_type(toml, target, root_name, "");
    return ok, target;
}

default_value_to_type :: (toml: Value, output: Any, name:string, parent_name:string) -> ok:=false {
    slot := output.value_pointer;
    info := output.type;

    if output.type.type == .STRUCT {
        struct_info :*Type_Info_Struct= xx output.type;
        if struct_info == type_info(Value) { cast(*Value, slot).* = copy(toml); return true; }
        if value_to_chrono(toml, slot, struct_info) return true;

        info = xx modify_type_info_cached(struct_info,, temp);

        expect(toml.kind, .TABLE, parent_name, name);
        done, ok := value_to_union(toml.table, slot, xx info, name); if done return ok;
    }
    return value_to_type_impl(toml, Any.{info, slot}, name, parent_name);
}

// Note meant to be called by the user directly, but instead to be used inside custom handlers
// output must hold a default initialized instance
value_to_type_impl :: (toml: Value, output: Any, name:string, parent_name:string) -> ok:=false {
    slot := output.value_pointer;
    info := output.type;

    if #complete info.type == {
    case .INTEGER;
        expect(toml.kind, .INT, parent_name, name);
        valid, low, high := range_check_and_store(toml.int_value, xx info, slot);
        if !valid { return_with_error("Value for %.% is out of range. Given % expected min % max %", parent_name, name, toml.int_value, low, high); }
    case .FLOAT;
        if toml.kind != .INT expect(toml.kind, .FLOAT, parent_name, name); // Allow int to float conversion
        if      info.runtime_size == 4 { cast(*float32, slot).* = ifx toml.kind == .INT then cast(float32, toml.int_value) else cast(float32, toml.float_value); }
        else if info.runtime_size == 8 { cast(*float64, slot).* = ifx toml.kind == .INT then cast(float64, toml.int_value) else               toml.float_value;  }
        else { return_with_error("Unsupported float size %", info.runtime_size); }
    case .BOOL;
        expect(toml.kind, .BOOL, parent_name, name);
        cast(*bool, slot).* = toml.bool_value;
    case .STRING;
        expect(toml.kind, .STRING, parent_name, name);
        cast(*string, slot).* = copy_string(toml.string_value);
    case .POINTER;
        if toml == context.toml.null_value return true; // Null pointer
        pointer_info :*Type_Info_Pointer= xx info;
        memory := alloc(pointer_info.pointer_to.runtime_size);
        initialize_memory(memory, pointer_info.pointer_to);
        cast(**void, slot).* = memory;
        return context.toml.custom_value_to_type(toml, Any.{pointer_info.pointer_to, memory}, name, parent_name);
    case .VOID;
        expect(toml.kind, .TABLE, parent_name, name);
        if toml.table.count != 0 { return_with_error("Expected empty table for %.%, got %", parent_name, name, toml.table.count);  }
    case .STRUCT;
        expect(toml.kind, .TABLE, parent_name, name);
        struct_info :*Type_Info_Struct= xx info;
        for member: struct_info.members {
            if member.flags & (.CONSTANT |.IMPORTED) continue;
            found, value_ptr := table_find_value_by_key(*toml, member.name);
            if found {
                ok:= context.toml.custom_value_to_type(value_ptr.*, Any.{member.type, slot + member.offset_in_bytes}, member.name, name);  if !ok return;
            } else if !(member.flags & .OVERLAY) && !array_find(member.notes, context.toml.optional_note) {
                return_with_error("Missing field %.%", struct_info.name, ifx member.name then member.name else "anonymous");
            }
        }
    case .ARRAY;
        expect(toml.kind, .ARRAY, parent_name, name);
        array_info :*Type_Info_Array= xx info;
        element_type := array_info.element_type;
        fill_array :: (toml_array: []Value, slot: *void, item_info: *Type_Info, parent_name:string) -> ok:=false {
            for idx: 0..toml_array.count-1 {
                item_slot := slot + item_info.runtime_size * idx;
                ok := context.toml.custom_value_to_type(toml_array[idx], Any.{item_info, item_slot}, "[item]", parent_name); if !ok return;
            }
            return true;
        }
        if #complete array_info.array_type == {
        case .FIXED;
            if toml.array.count != array_info.array_count { return_with_error("Fixed array %.% expected % items, got %", parent_name, name, array_info.array_count, toml.array.count); }
            ok := fill_array(toml.array, slot, element_type, name); if !ok return; // NOTE .FIXED is inside the struct so already initialized
        case .VIEW;
            array := cast(*[] u8, slot);
            array.data = alloc(toml.array.count * element_type.runtime_size);
            array.count = toml.array.count;
            initialize_memory(array.data, element_type, array.count);
            ok := fill_array(toml.array, array.data, element_type, name); if !ok return;
        case .RESIZABLE;
            array := cast(*[..] u8, slot);
            array_reserve(array, toml.array.count * element_type.runtime_size);
            array.count = toml.array.count;
            initialize_memory(array.data, element_type, array.count);
            ok := fill_array(toml.array, array.data, element_type, name); if !ok return;
        }
    case .ANY;
        if toml == context.toml.null_value return true; // Similar to null pointer
        any_value :*Any_Struct= xx slot;
        any_value.type = type_info(Value);
        any_value.value_pointer = alloc(any_value.type.runtime_size);
        any_value.value_pointer.(*Value).* = copy(toml); // No recursion so we don't rely on the custom_value_to_type
    case .ENUM;
        expect(toml.kind, .STRING, parent_name, name);
        enum_info :*Type_Info_Enum= xx info;
        found, index := array_find(enum_info.names, toml.string_value);
        if !found { return_with_error("String % is not a variant of enum %", toml.string_value, enum_info.name); }
        Reflection.set_enum_value(slot, enum_info, enum_info.values[index]);
    case .VARIANT;
        variant_info :*Type_Info_Variant= xx info;
        return context.toml.custom_value_to_type(toml, Any.{variant_info.variant_of, slot}, name, parent_name);
    case .PROCEDURE; #through; case .OVERLOAD_SET; #through; case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;      #through; case .CODE;         #through; case .UNTYPED_LITERAL;      #through;
    case .UNTYPED_ENUM; return_with_error("Deserialization to type % is not supported", info.type);
    }
    return true;
}

value_to_chrono ::  (toml: Value, slot: *void, info: *Type_Info) -> is_chrono:bool {
    if toml.kind != .DATETIME return false;

    if info == type_info(Chrono) { cast(*Chrono, slot).* = toml.datetime; return true;}
    if #complete toml.datetime.kind == {
    case .LOCAL_TIME;       if info == type_info(Time)           { cast(*Time, slot).*           = toml.datetime.time;            return true; }
    case .LOCAL_DATE;       if info == type_info(Date)           { cast(*Date, slot).*           = toml.datetime.date;            return true; }
    case .LOCAL_DATETIME;   if info == type_info(DateTime)       { cast(*DateTime, slot).*       = toml.datetime.datetime;        return true; }
    case .OFFSET_DATETIME;  if info == type_info(DateTimeOffset) { cast(*DateTimeOffset, slot).* = toml.datetime.datetime_offset; return true; }
    }
    return false;
}

value_to_union :: (toml_table: []KeyValue, slot: *void, struct_info: *Type_Info_Struct, parent_name: string) -> done:= true, ok:=false {
    if !(struct_info.textual_flags & .UNION_IS_TAGGED) return false;
    if toml_table.count == 0 && array_find(struct_info.notes, context.toml.optional_note) return true, true; // Since union behave like a value it can itself be optional: `union @TomlOptional kind:Type {}`
    if toml_table.count != 1  return_with_error("Tagged union %.% should have exactly one key-value pair", parent_name, struct_info.name); // No superfluous values allowed here
    if !toml_table[0].key return_with_error("Tagged union %.% requires a non-empty key, name the member or use a modified Type_Info", parent_name, struct_info.name);

    // Determine the active member
    found := false;
    active_member_idx :s64;
    for array_view(struct_info.members, 1) if it.name == toml_table[0].key {
        active_member_idx = it_index + 1;
        found = true;
        break;
    }
    if !found then return_with_error("Key % not found in tagged union %", toml_table[0].key, struct_info.name);
    active_member := *struct_info.members[active_member_idx]; // We set the members's value at the end so that the tag is set before we recurse into the value

    // Find the corresponding tag value
    tag_member := *struct_info.members[0];
    intlike_uniontag_from_member_index :: (struct_info: *Type_Info_Struct, active_member_idx: s64, int_info: *Type_Info_Integer) -> ok:=false, tag_value:s64, requires_check:bool {
        for struct_info.tagged_union_bindings if it.member_index == active_member_idx {
            ok, tag_value := get_integer_value(*it.constant_value, int_info); // Works for negative values as well
            return ok, tag_value, true;
        } // If there is no binding, use the member index as tag VALUE (not as enum.values.index)
        return true, (active_member_idx - 1), false; // -1 as first member is the tag
    }

    if tag_member.type.type == {
    case .ENUM;
        tag_info :*Type_Info_Enum= xx tag_member.type;
        ok, tag_value, requires_check := intlike_uniontag_from_member_index(struct_info, active_member_idx, xx tag_info.internal_type); if !ok return_with_error("Tagged Union tag constant value % cannot be represented in s64 for %.%", tag_value, parent_name, struct_info.name);
        if requires_check && !(array_find(tag_info.values, tag_value)) return_with_error("Tagged Union tag value % not found in enum %", tag_value, tag_info.name);
        Reflection.set_enum_value(slot + tag_member.offset_in_bytes, tag_info, tag_value);
    case .INTEGER;
        ok, tag_value, requires_check := intlike_uniontag_from_member_index(struct_info, active_member_idx, xx tag_member.type); if !ok return_with_error("Tagged Union tag constant value % cannot be represented in s64 for %.%", tag_value, parent_name, struct_info.name);
        valid, low, high := range_check_and_store(tag_value, xx tag_member.type, slot + tag_member.offset_in_bytes);
        if !valid { return_with_error("Tag for %.% is out of range. Given % expected min % max %", toml_table[0].key, parent_name, tag_value, low, high); }
    case .TYPE;
        cast(**Type_Info, slot + tag_member.offset_in_bytes).* = active_member.type;
    case; return_with_error("Tagged Union tag type % not supported", tag_member.type.type);
    }

    // Deserialize the active member's value
    ok := context.toml.custom_value_to_type(toml_table[0].value, Any.{active_member.type, slot + active_member.offset_in_bytes}, toml_table[0].key, parent_name);
    return true, ok;
}

expect :: inline (given: Value.Kind, expected: Value.Kind, struct_name: string, member_name: string) #expand {
    if given != expected { log_error("Wrong type for %.%, expected %, got % ", struct_name, member_name, expected, given); `return; }
}

#scope_module

//
// Generic memory utilities
//

initialize_memory :: (memory: *void, info: *Type_Info, count:s64=1) {
    if count <= 0 || info.runtime_size <= 0 return;
    total_size := count * info.runtime_size;

    if info.type == {
    case .STRUCT;
        struct_info :*Type_Info_Struct= xx info;
        if struct_info.initializer {
            current := memory;
            for 0..count-1 {
                struct_info.initializer(current);
                current += struct_info.runtime_size;
            }
            return;
        }
    case .ARRAY;
        array_info :*Type_Info_Array= xx info;
        if array_info.array_type == .FIXED {
            initialize_memory(memory, array_info.element_type, array_info.array_count);
            return;
        }
    case .VARIANT;
        variant_info :*Type_Info_Variant= xx info;
        initialize_memory(memory, variant_info.variant_of);
        return;
    }
    memset(memory, 0, total_size);
}

get_integer_value :: (data: *void, info: *Type_Info_Integer) -> ok:=false, value:s64=0 {
    if info.runtime_size == {
        case 1; return true, ifx info.signed then data.(*s8) .*.(s64) else data.(*u8) .*.(s64);
        case 2; return true, ifx info.signed then data.(*s16).*.(s64) else data.(*u16).*.(s64);
        case 4; return true, ifx info.signed then data.(*s32).*.(s64) else data.(*u32).*.(s64);
        case 8; return true, ifx info.signed then data.(*s64).*.(s64) else {
            output := data.(*u64).*;
            if output > 0x7fff_ffff_ffff_ffff { return_with_error("Value % is out of s64 range", output); }
            output.(s64, no_check);
        };
        case; assert(false); return;
    }
}

range_check_and_store :: (value: s64, info: *Type_Info_Integer, pointer: *void) -> ok:bool, low:s64, high:s64 {
    low, high :s64= ---;
    if info.signed || info.runtime_size == 8 {
        low, high =    Reflection.signed_integer_range_from_size(info.runtime_size);
    } else {
        ulow, uhigh := Reflection.unsigned_integer_range_from_size(info.runtime_size);
        low, high = ulow.(s64), uhigh.(s64);
    }
    if (value < low) || (value > high)  return false, low, high;

    if info.signed if info.runtime_size == {
        case 1; pointer.(*s8) .* = xx,no_check value;
        case 2; pointer.(*s16).* = xx,no_check value;
        case 4; pointer.(*s32).* = xx,no_check value;
        case 8; pointer.(*s64).* = xx,no_check value;
    }
    else if info.runtime_size == {
        case 1; pointer.(*u8) .* = xx,no_check value;
        case 2; pointer.(*u16).* = xx,no_check value;
        case 4; pointer.(*u32).* = xx,no_check value;
        case 8; pointer.(*u64).* = xx,no_check value;
    }
    return true, low, high;
}

auto_release_temp_maybe :: (loc := #caller_location) #expand {
    is_temp := context.allocator.proc == temporary_allocator_proc;
    __mark := get_temporary_storage_mark();
    `defer if !is_temp set_temporary_storage_mark(__mark, loc);

    // Toml specific
    `defer context.toml.type_info_cache = .{};
    `defer context.toml.index_maps = [..]Table(string, s64).{};
}
