
main :: () {
    contents := read_entire_file("toml.toml");
    toml     := parse(contents);
    print_value(toml);

THE_STRING :: #string DONE
orange = false
banana = 23.3
apple = {a =31, b = "Y", c = 'Y'}
DONE
    Hello :: enum {
        X;
        Y;
    }
    Inner :: struct {
        a: s64;
        b: s64;
        c: Hello;
    }
    MyStruct :: struct {
        orange: bool;
        banana: float64;
        apple : Inner;
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
    // print("\n%\n", info_enum.name);

    for member: info_enum.members {
        // print("name: %\n", member.name);
        found := false;
        for value.table {
            if it.key == member.name {
                // TODO delay parsing literal till here for optimal conversions and making strings permanent
                found = true;
                // print("value: `%`\n", it.value);
                slot := target + member.offset_in_bytes;
                 // TODO typecheck and range check
                 // Prob use Reflection.jai
                member_info := member.type;
                if member_info.type == { // #complete
                case .INTEGER;
                    // TODO checked narrowing conversions
                    memcpy(slot, (cast(*u8) *it.int_value), member.type.runtime_size);
                case .FLOAT;
                    // TODO checked narrowing conversion
                    memcpy(slot, (cast(*u8) *it.float_value), member.type.runtime_size);
                case .BOOL;
                    <<slot = cast(u8) it.bool_value;
                // case .STRING;
                //     <<slot = cast(u8) it.string_value;
                case .STRUCT;
                    if it.type != .TABLE {
                        log_error("Error: field `%` is not a struct", member.name);
                        exit(1);
                    }
                    // handle offset_into_constant_storage
                    // handle flags
                    // make length safe
                    struct_member_info := cast(*Type_Info_Struct) member_info;
                    deserialize(it.value, slot, struct_member_info);
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
                        // TODO range check
                        set_enum_value(slot, enum_member_info, it.int_value);
                    case;
                        log_error("The value for enum % was a % instead of a string or int", enum_member_info.name, it.type);
                        exit(1);
                    }
                case;
                    log_error("Type % is not yet supported", member_info.type);
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
    case .STRING; print("%", value.string_value);
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

#load "parser.jai";
#import "Reflection";
