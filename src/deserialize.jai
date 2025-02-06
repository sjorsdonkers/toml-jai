deserialize :: (contents: string, $Target: Type) -> ok:=false, value:Target=.{} {
    ok, value := parse_string_to_value_shared_memory(contents,, scoped_pool()); if !ok return;
    ok=, target := value_to_type(value, Target);
    return ok, target;
}

value_to_type :: (value: Value, $Target: Type) -> ok:=false, value:Target=.{} {
    info :: type_info(Target);
    target :Target;
    ok := value_to_type(value, *target, info, info.name); // Would be nice to provide a shared_memory version as well without having to wire a `shared` flag all the way through
    return ok, target;
}

#if CUSTOM_HANDLERS {
    #add_context toml_custom_value_to_type:= (toml: Value, slot: *void, info:*Type_Info, name:string, parent_name:string) -> done:bool, ok:bool { return false, true; };
}

// Note meant to be called by the user directly, but instead to be used inside custom deserializers
// slot is already initialized memory
value_to_type :: (toml: Value, slot: *void, info: *Type_Info, name:string="", parent_name:string="") -> ok:=false {
    #if CUSTOM_HANDLERS {
        done, ok := context.toml_custom_value_to_type(toml, slot, info, name, parent_name);
        if done return ok;
    }

    if #complete info.type == {
    case .INTEGER;
        expect(toml.type, .INT, parent_name, name);
        valid, low, high := range_check_and_store(toml.int_value, xx info, slot);
        if !valid { return_with_error("Value for %.% is out of range. Given % expected min % max %", parent_name, name, toml.int_value, low, high); }
    case .FLOAT;
        if toml.type != .INT expect(toml.type, .FLOAT, parent_name, name); // Allow int to float conversion
        if      info.runtime_size == 4 { cast(*float32, slot).* = ifx toml.type == .INT then cast(float32, toml.int_value) else cast(float32, toml.float_value); }
        else if info.runtime_size == 8 { cast(*float64, slot).* = ifx toml.type == .INT then cast(float64, toml.int_value) else               toml.float_value;  }
        else { return_with_error("Unsupported float size %", info.runtime_size); }
    case .BOOL;
        expect(toml.type, .BOOL, parent_name, name);
        cast(*bool, slot).* = toml.bool_value;
    case .STRING;
        expect(toml.type, .STRING, parent_name, name);
        cast(*string, slot).* = copy_string(toml.string_value);
    case .POINTER;
        if toml == NULL_VALUE return true; // Null pointer

        pointer_info :*Type_Info_Pointer= xx info;
        memory := alloc(pointer_info.pointer_to.runtime_size);
        initialize_memory(memory, pointer_info.pointer_to);
        cast(**void, slot).* = memory;
        return value_to_type(toml, memory, pointer_info.pointer_to, name, parent_name);
    case .VOID;
        expect(toml.type, .TABLE, parent_name, name);
        if toml.table.count != 0 { return_with_error("Expected empty table for %.%, got %", parent_name, name, toml.table.count);  }
    case .STRUCT;
        if info == type_info(Value) { cast(*Value, slot).* = copy(toml); return true; } // If we encounter a Toml.Value at any point just copy it
        if value_to_chrono(toml, slot, info) return true;
        expect(toml.type, .TABLE, parent_name, name);
        struct_info :*Type_Info_Struct= xx info;

        if array_find(struct_info.notes, "SumType") { return value_to_sumtype(toml.table, slot, struct_info, name); }
        for member: struct_info.members {
            if member.flags & (.CONSTANT |.IMPORTED) continue;
            found := false;
            for toml.table if it.key == member.name {
                found = true;
                ok:= value_to_type(it.value, slot + member.offset_in_bytes, member.type, member.name, name);  if !ok return;
                break;
            }
            if !found && !array_find(member.notes, "TomlOptional") then return_with_error("Missing field %.%", struct_info.name, member.name);
        }
    case .ARRAY;
        expect(toml.type, .ARRAY, parent_name, name);
        array_info :*Type_Info_Array= xx info;
        element_type := array_info.element_type;

        fill_array :: (toml_array: []Value, slot: *void, item_info: *Type_Info, parent_name:string) -> ok:=false {
            for idx: 0..toml_array.count-1 {
                item_slot := slot + item_info.runtime_size * idx;
                ok := value_to_type(toml_array[idx], item_slot, item_info, "[item]", parent_name); if !ok return;
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
        if toml == NULL_VALUE return true; // Similar to null pointer

        any_value :*Any_Struct= xx slot;
        if #complete toml.type == {
        case .BOOL;     any_value.type = type_info(type_of(Value.bool_value));
        case .INT;      any_value.type = type_info(type_of(Value.int_value));
        case .FLOAT;    any_value.type = type_info(type_of(Value.float_value));
        case .STRING;   any_value.type = type_info(type_of(Value.string_value));
        case .DATETIME; any_value.type = type_info(type_of(Value.datetime));
        case .ARRAY;    any_value.type = type_info(type_of(Value.array));
        case .TABLE;    any_value.type = type_info(type_of(Value.table));
        }
        any_value.value_pointer = alloc(any_value.type.runtime_size);
        initialize_memory(any_value.value_pointer, any_value.type);
        return value_to_type(toml, any_value.value_pointer, any_value.type, name, parent_name);
    case .ENUM;
        expect(toml.type, .STRING, parent_name, name);
        enum_info :*Type_Info_Enum= xx info;

        found, index := array_find(enum_info.names, toml.string_value);
        if !found { return_with_error("String % is not a variant of enum %", toml.string_value, enum_info.name); }
        Reflection.set_enum_value(slot, enum_info, enum_info.values[index]);
    case .VARIANT;
        variant_info :*Type_Info_Variant= xx info;
        return value_to_type(toml, slot, variant_info.variant_of, name, parent_name);
    case .PROCEDURE; #through; case .OVERLOAD_SET; #through; case .POLYMORPHIC_VARIABLE; #through;
    case .TYPE;      #through; case .CODE;         #through; case .UNTYPED_LITERAL;      #through;
    case .UNTYPED_ENUM; return_with_error("Deserialization to type % is not supported", info.type);
    }
    return true;
}

value_to_chrono ::  (toml: Value, slot: *void, info: *Type_Info) -> is_chrono:bool {
    if toml.type != .DATETIME return false;

    if info == type_info(Chrono) { cast(*Chrono, slot).* = toml.datetime; return true;}
    if #complete toml.datetime.type == {
    case .LOCAL_TIME;       if info == type_info(Time)           { cast(*Time, slot).*           = toml.datetime.time;            return true; }
    case .LOCAL_DATE;       if info == type_info(Date)           { cast(*Date, slot).*           = toml.datetime.date;            return true; }
    case .LOCAL_DATETIME;   if info == type_info(DateTime)       { cast(*DateTime, slot).*       = toml.datetime.datetime;        return true; }
    case .OFFSET_DATETIME;  if info == type_info(DateTimeOffset) { cast(*DateTimeOffset, slot).* = toml.datetime.datetime_offset; return true; }
    }
    return false;
}

value_to_sumtype :: (toml_table: []KeyValue, slot: *void, struct_info: *Type_Info_Struct, parent_name: string) -> ok:=false {
    valid, tag_member, union_member, tag_info, union_info:= is_valid_sumtype(struct_info);
    if !valid { return_with_error("SumType % is not valid", struct_info.name); }

    if toml_table.count != 1  return_with_error("SumType % should have exactly one key-value pair", struct_info.name);

    for tag_info.names if it == toml_table[0].key {
        Reflection.set_enum_value(slot + tag_member.offset_in_bytes, tag_info, tag_info.values[it_index]);
        active_variant:= union_info.members[it_index];
        return value_to_type(toml_table[0].value, slot + union_member.offset_in_bytes + active_variant.offset_in_bytes, active_variant.type, toml_table[0].key, parent_name);
    }
    return_with_error("Key % is not an enum variant of SumType %", toml_table[0].key, struct_info.name);
}

is_valid_sumtype :: (struct_info: *Type_Info_Struct) -> bool, tag_member:*Type_Info_Struct_Member=null, union_member:*Type_Info_Struct_Member=null, tag_info:*Type_Info_Enum=null, union_info:*Type_Info_Struct=null {
    if struct_info.members.count != 2                                      return false;
    tag_member, union_member:= *struct_info.members[0], *struct_info.members[1];
    if tag_member.type.type != .ENUM || union_member.type.type != .STRUCT  return false;
    tag_info :*Type_Info_Enum= xx tag_member.type;
    union_info :*Type_Info_Struct= xx union_member.type;
    if union_info.textual_flags & .UNION == 0                              return false;
    if tag_info.values.count != union_info.members.count                   return false;
    return true, tag_member, union_member, tag_info, union_info;
}

expect :: inline (given: Value.Type, expected: Value.Type, struct_name: string, member_name: string) #expand {
    if given != expected { `return_with_error("Wrong type for %.%, expected %, got % ", struct_name, member_name, expected, given); }
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

scoped_pool :: () -> Allocator #expand {
    pool: Flat_Pool;
    a: Allocator;
    a.proc = flat_pool_allocator_proc;
    a.data = *pool;
    `defer fini(*pool);
    return a;
}

#scope_file
#load "parser.jai";
Reflection :: #import "Reflection";
#import "Flat_Pool";
