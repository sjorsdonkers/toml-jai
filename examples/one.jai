
main :: () {
    contents := read_entire_file("toml.toml");
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    toml := Toml.deserialize(contents, Toml.Value,, allocator=heap);
    log("dfg");
    log("dfg");
    print(Toml.serialize(toml));
    log("dfg");
    log("dfg");


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
    Filename :: #type,distinct string;
    MyStruct :: struct {
        orange: bool;
        banana: float;
        apple : Inner;
        kiwi  : [..] Q;
        horse :Filename;
    }

    toml2 := Toml.deserialize(THE_STRING, Toml.Value);
    Toml.print_value(toml2);
    print("\n");
    my_struct := Toml.deserialize(toml2, MyStruct);
    print("MyStruct: %\n", my_struct);

    Guy :: struct {
        union {
            Banana: void;
            Apple: struct { a: u8; b: string;};
            Orange: string;
        };
        tag: enum {
            Banana;
            Apple;
            Orange;
        };
    }
    void_banana := Toml.deserialize("", Guy);
    print("void_banana: %\n", void_banana);
    print("void_banana: %\n", void_banana.Banana);

    SUM :: #string DONE
Apple = {a = 32, b = 'Y'}
DONE
    apple := Toml.deserialize(SUM, Guy);
    print("struct_apple: %\n", apple);
    print("struct_apple: %\n", apple.Apple);


    left := Toml.deserialize("a.b = {c.d = 1}", Toml.Value);
    right := Toml.deserialize("a.b.c.d = 1", Toml.Value);
    assert(left == right);
}

using Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";
