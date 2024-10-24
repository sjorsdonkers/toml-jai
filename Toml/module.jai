
main :: () {
    contents := read_entire_file("toml.toml");
    toml     := parse(contents);
    print_value(toml);

THE_STRING :: #string DONE
orange = 7
banana = 23.3
apple = {a =31, b = 2}
DONE
    MyStruct :: struct {
        orange: s64;
        banana: float64;
        apple : Inner;
    }
    Inner :: struct {
        a: s64;
        b: s64;
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
                if it.type == {
                case Value_Type.INT;
                    // TODO checked narrowing conversions
                    memcpy(slot, (cast(*u8) *it.int_value), member.type.runtime_size);
                case Value_Type.FLOAT;
                    // TODO checked narrowing conversion
                    memcpy(slot, (cast(*u8) *it.float_value), member.type.runtime_size);
                case Value_Type.TABLE;
                    if member_info.type != .STRUCT {
                        log_error("Error: field `%` is not a struct", member.name);
                        exit(1);
                    }
                    // handle offset_into_constant_storage
                    // handle flags
                    // make length safe
                    struct_member_info := cast(*Type_Info_Struct) member_info;
                    deserialize(it.value, slot, struct_member_info);
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
    if value.type == {
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
