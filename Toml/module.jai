
main :: () {
    contents := read_entire_file("toml.toml");
    toml     := parse(contents);
    print_value(toml);

THE_STRING :: #string DONE
orange = 7
banana = 23.3
DONE
    toml2 := parse(THE_STRING);
    print_value(toml2);
    my_struct := deserialize(toml2, MyStruct);
    print("MyStruct: %\n", my_struct);
}

deserialize :: (value: Value, $Target: Type) -> Target {
    target : Target;
    info_enum := type_info(Target);
    print("\n%\n", info_enum.name);

    for member: info_enum.members {
        print("name: %\n", member.name);
        for value.table {
            if it.key == member.name {
                print("value: `%`\n", it.value);
                slot := (cast(*u8) *target) + member.offset_in_bytes;
                 // TODO typecheck and range check
                 // Prob use Reflection.jai
                memcpy(slot, (cast(*u8) *it.int_value), member.type.runtime_size);
                break;
            }
        }
        // return info_enum.names[it_index];
    }
    return target;
    // return Target.{value=4};
}

MyStruct :: struct {
    orange: s64;
    banana: float64;
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
