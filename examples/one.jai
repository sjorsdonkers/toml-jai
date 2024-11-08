
main :: () {
    contents := read_entire_file("toml.toml");
    toml     := Toml.parse(contents); //,, allocator=temp
    // for 0..contents.count-1 {
    //     contents[it] = #char "p";
    // }
    print_value(toml);

THE_STRING :: #string DONE
orange = false
banana = 23.3
apple = {a = 32, b = 'Y', c = 'Y'}
kiwi = [
    {q = 2},
    {q = -3},
    {q = 4},
]
horse = "Mai"
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
        q: s16;
    }
    Filename       :: #type,distinct string;
    MyStruct :: struct {
        orange: bool;
        banana: float;
        apple : Inner;
        kiwi  : [..] Q;
        horse :Filename;
    }

    toml2 := Toml.parse(THE_STRING);
    print_value(toml2);
    print("\n");
    my_struct := Toml.deserialize(toml2, MyStruct);
    print("MyStruct: %\n", my_struct);
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
