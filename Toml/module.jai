
main :: () {
    contents := read_entire_file("toml.toml");
    toml     := parse(contents);
    print_value(toml);

THE_STRING :: #string DONE
orange = false
banana = 23.3
apple = {a = 32, b = 'Y', c = 'Y'}
kiwi = [
    {q = 2},
    {q = 3},
    {q = 4},
]
DONE
    Hello :: enum {
        X;
        Y;
    }
    Inner :: struct {
        a: u8;
        b: string;
        c: Hello;
    }
    Q :: struct {
        q: u8;
    }
    MyStruct :: struct {
        orange: bool;
        banana: float;
        apple : Inner;
        kiwi  : [3] Q;
    }

    toml2 := parse(THE_STRING);
    print_value(toml2);
    my_struct := deserialize(toml2, MyStruct);
    print("MyStruct: %\n", my_struct);
}

deserialize :: (value: Value, $Target: Type) -> Target {
    target : Target;
    bytes := cast(*u8) *target;
    info := type_info(Target);
    deserialize(value, bytes, info);
    return target;
}

deserialize :: (value: Value, target: *u8, info_enum: *Type_Info_Struct) {
    for member: info_enum.members {
        found := false;
        for value.table {
            if it.key == member.name {
                found = true;
                slot := target + member.offset_in_bytes;
                member_info := member.type;
                if member_info.type == { // #complete
                case .INTEGER;
                    expect(it.type, .INT, info_enum.name, member.name);
                    // TODO support u64, delay parsing till here so we known wheter to parse signed or unsigned / or store u64 as well
                    int_info := cast(*Type_Info_Integer)member_info;
                    valid, low, high := range_check_and_store(it.int_value, int_info, slot);
                    if !valid {
                        log_error("Value for %.% is out of range. Given % expected min % max %", info_enum.name, member.name, it.int_value, low, high);
                        exit(1);
                    }
                case .FLOAT;
                    expect(it.type, .FLOAT, info_enum.name, member.name);
                    if member_info.runtime_size == 4 {
                        <<cast(*float) slot = cast(float) it.float_value; // TODO not lossless, delay parsing
                    } else {
                        assert(member_info.runtime_size == 8);
                        <<cast(*float64) slot = it.float_value;
                    }
                case .BOOL;
                    expect(it.type, .BOOL, info_enum.name, member.name);
                    <<cast(*bool) slot = it.bool_value;
                case .STRING;
                    expect(it.type, .STRING, info_enum.name, member.name);
                    // TODO deepcopy to callers allocator
                    <<cast(*string) slot = it.string_value;
                // case .POINTER; // hmm put in permanent memory and point to the value?
                // case .VOID; // Do we want to allow this to be an empty table?
                case .STRUCT;
                    expect(it.type, .TABLE, info_enum.name, member.name);
                    // handle offset_into_constant_storage
                    // handle flags
                    // make length safe
                    struct_member_info := cast(*Type_Info_Struct) member_info;
                    deserialize(it.value, slot, struct_member_info);
                case .ARRAY;
                    expect(it.type, .ARRAY, info_enum.name, member.name);
                    array_info := cast(*Type_Info_Array) member_info;
                    element_type := array_info.element_type;
                    if array_info.array_type == {
                        case .FIXED;
                            if it.array.count != array_info.array_count {
                                log_error("Fixed array %.% expected % items, got %", info_enum.name, member.name, array_info.array_count, it.array.count);
                                exit(1);
                            }
                            for idx: 0..array_info.array_count-1 {
                                array_slot := slot + element_type.runtime_size * idx;
                                assert(element_type.type == .STRUCT);
                                fake := cast(*Type_Info_Struct) element_type; // TODO remove after refator
                                deserialize(it.array[idx], array_slot, fake);
                            }

                        case .VIEW;
                        // TODO Same as POINTER
                        log_error("Deserialization to type ARRAY VIEW is not supported yet");
                        exit(1);
                        case .RESIZABLE;
                        // TODO
                        log_error("Deserialization to type ARRAY RESIZABLE is not supported yet");
                        exit(1);
                    }
                // case .ANY; // Probably similar to .POINTER
                case .ENUM;
                    enum_member_info := cast(*Type_Info_Enum) member_info;
                    if it.type == {
                    case .STRING;
                        found, index := array_find(enum_member_info.names, it.string_value);
                        if !found {
                            log_error("String % is not a variant of enum %", it.string_value, enum_member_info.name);
                            exit(1);
                        }
                        set_enum_value(slot, enum_member_info, enum_member_info.values[index]);
                    case .INT;
                        found := array_find(enum_member_info.values, it.int_value);
                        if !found {
                            log_error("Value % is not a variant of enum %", it.int_value, enum_member_info.name);
                            exit(1);
                        }
                        set_enum_value(slot, enum_member_info, it.int_value);
                    case;
                        log_error("Wrong type for %.%, expected STRING or INT, got % ", info_enum.name, member.name, it.type);
                        exit(1);
                    }
                // case VARIANT recurse till real type see 180_type_variants get_one_step_inside(..)
                // variant_info := cast(*Type_Info_Variant) info;
                // recurse_into_this(variant_info.variant_of);
                case .PROCEDURE;            #through;
                case .OVERLOAD_SET;         #through;
                case .POLYMORPHIC_VARIABLE; #through;
                case .TYPE;                 #through;
                case .CODE;                 #through;
                case;
                    log_error("Deserialization to type % is not supported", member_info.type);
                    exit(1);
                }
                break;
            }
        }
        if !found {
            log_error("Error: missing field `%` for struct `%`", member.name, info_enum.name);
            exit(1);
        }
    }
}

print_value :: (value : Value, indent:="") {
    if #complete value.type == {
    case .STRING; print("'%'", value.string_value);
    case .INT; print("%", value.int_value);
    case .FLOAT; print("%", value.float_value);
    case .BOOL; print("%", value.bool_value);
    case .ARRAY;
        print("[\n");
        new_indent := tprint("%  ", indent);
        for val: value.array {
            print("%", new_indent);
            print_value(val, new_indent);
            print(",\n");
        }
        print("%]", indent);
    case .TABLE;
        print("{\n");
        new_indent := tprint("%  ", indent);
        for keyval: value.table {
            print("%0% ", new_indent, keyval.key);
            if keyval.type != .TABLE { print("= "); }
            print_value(keyval.value, new_indent);
            print("\n");
        }
        print("%}", indent);
    }
}

expect :: inline (given: Value_Type, expected: Value_Type, struct_name: string, member_name: string) {
    if given != expected {
        log_error("Wrong type for %.%, expected %, got % ", struct_name, member_name, expected, given);
        exit(1);
    }
}

#load "parser.jai";
#import "Reflection";
