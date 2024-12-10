main :: () {
    // TOML data is not expected to multi-GB, so just read the entire file. For easy cleanup of the memory allocated for
    // the returned structs we can push an allocator. The type Toml.Value can be used deserialization target for any TOML data.
    contents := read_entire_file("data/inline_table.toml");
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    toml_value := Toml.deserialize(contents, Toml.Value,, allocator=heap);
    Toml.print_value(toml_value); print("\n");

    // We can also deserialize the TOML data into a struct. The struct must have the same fields as the TOML data.
    // The struct can have additional fields that are not present in the TOML data, in this case the fields will be initialized to their default values.
    // The TOML can have additional fields that are not present in the struct, in this case the fields will be ignored.
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
    Filename :: #type,distinct string; // #type,isa Variants are supported as well
    MyStruct :: struct {
        orange: bool;
        banana: float;
        apple : Inner;
        kiwi  : [..] Q;
        horse :Filename;
    }

    my_struct := Toml.deserialize(THE_STRING, MyStruct);
    print("MyStruct: %\n", my_struct);

    // Except for untagged-unions all run-time types are supported.
    // Meaning, union are only supported if they are in the shape of a sum-type. A sum-type is defined as a struct with a tag enum
    // and a union, where both have the same number of members. The tag indices should correspond to those of the union variants.
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
    SUM :: #string DONE
Apple = {a = 32, b = 'Y'}
DONE
    apple := Toml.deserialize(SUM, Guy);
    print("struct_apple: %\n", apple);
    print("struct_apple: %\n", apple.Apple);

    // If the TOML data does not contain a field that is present in the struct, the field will be initialized to its default value.
    // Jai's initialization of unions is wack. So instead unions are initialized always initialized to the first variant.
    void_banana := Toml.deserialize("", Guy);
    print("void_banana: %\n", void_banana);
    print("void_banana: %\n", void_banana.Banana);

    // For convenience Toml.Value comes with an equality operator and copy procedure.
    left := Toml.deserialize("a.b = {c.d = 1}", Toml.Value);
    right := Toml.deserialize("a.b.c.d = 1", Toml.Value);
    assert(left == right);

    // Jai does not have commonly used types for dates and times. Most likely you do not want those provided by some Toml module.
    // As such date/times are returned as strings. You the user can choose to use their own RFC 3339 parser. Or use the one defined here in Toml/datetime.jai.
    MyTime :: struct {
        t: string;
    }
    chrono := Toml.deserialize("t = 1979-05-27 07:32:00Z", MyTime);
    print("chrono: %\n", chrono);
    assert(chrono.t == "1979-05-27 07:32:00Z");

    // Pointers, ANY, VIEW and RESIZABLE arrays are supported at any depth in the struct definition.
    // These types that are referencing memory elsewhere will have new memory allocated for them with the context allocator.
    reference_types();
}

reference_types :: () {
    // POINTER
    Inner :: struct {
        str: string;
    }
    Outer :: struct {
        p_s16: *s16;
        p_inner: *Inner;
    }
    pointers_toml := Toml.deserialize("p_s16 = 36\np_inner = {str = 'Barry'}", Outer);
    print("pointers_toml: %\n", pointers_toml);
    print("pointers_toml.p_s16: %\n",   <<pointers_toml.p_s16  );
    print("pointers_toml.p_inner: %\n", <<pointers_toml.p_inner);

    Getal :: #type,distinct u8;

    // Pointer to fixed array with initializer
    Vingt :: struct       {
        number : s8=20;
        getal: Getal= 23;
    }
    Fixed_Array :: struct {
        p_quatre: *[4]Vingt;
    }
    quatre_vingt := Toml.deserialize("p_quatre = [{getal = 9}, {getal = 4}, {number = 3}, {}]", Fixed_Array);
    log("quatre_vingt: %\n", <<quatre_vingt.p_quatre);
    assert((<<quatre_vingt.p_quatre)[0].number == 20);
    assert((<<quatre_vingt.p_quatre)[2].getal == 23);

    // Pointer to variant
    DefaultStruct :: struct {
        a: string="Anton";
        b: s8;
    }
    DefaultVariant :: #type,distinct DefaultStruct;
    MyVar :: struct {
        p_variant: *DefaultVariant;
    }
    mutant := Toml.deserialize("p_variant.b = 3", MyVar);
    print("mutant: %\n", <<mutant.p_variant);
    assert(mutant.p_variant.a == "Anton");

    // Pointer to struct with using (no impl required)
    MyUsing :: struct {
        using a: Vingt;
    }
    MyPtrUsing :: struct {
        p_using: *MyUsing;
    }
    use20 := Toml.deserialize("[p_using]\nnumber = 6", MyPtrUsing);
    print("use20: %\n", <<use20.p_using);
    assert(use20.p_using.getal == 23);

    // Union with first having an initializer
    MyUnionStruct :: struct {
        tag : enum {
            FIRST;
            SECOND;
        }
        union {
            first: Vingt;
            second: string;
        }
    }
    un := Toml.deserialize("", MyUnionStruct);
    print("un: %\n", un.first);
    assert(un.first.number == 20);
    assert(un.first.getal == 23);

    // Pointer to union
    MyUnionPtr :: struct {
        p_union: *MyUnionStruct;
    }
    un_ptr := Toml.deserialize("p_union.FIRST.number = 3", MyUnionPtr);
    print("un_ptr: %\n", un_ptr.p_union.first);
    assert(un_ptr.p_union.first.number == 3);
    assert(un_ptr.p_union.first.getal == 23);

    // ARRAY VIEW
    Array_View :: struct {
        ocean: []s16;
    }
    arrayview_toml := Toml.deserialize("ocean = [1, 2, 3]", Array_View);
    print("arrayview_toml: %\n", arrayview_toml);
    assert(arrayview_toml.ocean[2] == 3);

    // ANY
    Amy :: struct {
        andy: Any;
    }
    toml4 := Toml.deserialize("andy = 3", Amy);
    assert("{3}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = 'hello'", Amy);
    assert("{\"hello\"}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = 3.3", Amy);
    assert("{3.3}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = true", Amy);
    assert("{true}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = [1, 7, 3]", Amy);
    assert("{[1, 7, 3]}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = [1, 'd', 3]", Amy);
    print("%\n", toml4);

    AnyAndy :: struct {
        any_andy: s16;
        any_amy: s16;
    }
    OtherAndy :: struct {
        other_andy: string;
        other_amy: string;
    }
    toml5 := Toml.deserialize("[[andy]]\nany_andy = 9\nany_amy = 8\n[[andy]]\nother_andy = 'Peter'\nother_amy = 'Derick'", Amy);
    andies := cast(*[]Toml.Value) toml5.andy.value_pointer;
    any_andy := Toml.deserialize((<<andies)[0], AnyAndy);
    assert("{9, 8}" == tprint("%", any_andy));
    other_andy := Toml.deserialize((<<andies)[1], OtherAndy);
    assert("{\"Peter\", \"Derick\"}" == tprint("%", other_andy));
}

using Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";
