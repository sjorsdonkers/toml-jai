
main :: () {
    read_parse_print("strings.toml");
}

read_parse_print :: (filepath: string) {
    contents := read_entire_file(filepath);
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    toml := Toml.deserialize(contents, Toml.Value,, allocator=heap);
    print_value(toml);
}

Toml :: #import, file "../Toml/module.jai";
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
