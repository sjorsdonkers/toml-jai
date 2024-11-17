


main :: () {
    Expect :: struct {
        nom: string;
        expected: Sum_Type.Option(s64);
    }
    none := Toml.deserialize("nom = 'Tim'", Expect);
    print("none: %\n", none);
    some := Toml.deserialize("nom = 'Tim'\nexpected = 23", Expect);
    print("some: %\n", some);
    print("expected: %\n", Sum_Type.unwrap(some.expected)); // TODO how to print these nicely easily?

    // you're here: Missing field Guy.Apple in one.jai
}

Toml :: #import, file "../Toml/module.jai";
Sum_Type :: #import, file "../../sum_type-jai/Sum_Type/module.jai";
#import "Basic";
#import "File";

#scope_file

print_value :: (value : Toml.Value, indent:="") {
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
