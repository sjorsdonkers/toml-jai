main :: () {
    // TOML data is not expected to multi-GB, so just read the entire file. For easy cleanup of the memory allocated for
    // the returned structs we can push an allocator. The type Toml.Value can be used deserialization target for any TOML data.
    contents := read_entire_file("data/inline_table.toml");
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    ok, toml_value := Toml.deserialize(contents, Toml.Value,, allocator=heap); assert(ok);
    ok_toml, toml := Toml.serialize(toml_value); assert(ok_toml);
    print("%\n", toml);

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

    ok=, my_struct := Toml.deserialize(THE_STRING, MyStruct); assert(ok);
    print("MyStruct: %\n", my_struct);
    ok=, as_value := Toml.serialize(my_struct); assert(ok);
    log("serialize:\n%", as_value);

    // All run-time types are supported.
    // A tagged union / sum-type requires the tag in the toml to be correctly matching the set union
    // To make the TAG optional and prevent incorrect tags you can declare the union's tag member with a note like @UnionTag:mytag
    // NOTE: Make sure the union initializes to the first variant by disabling initialization of the other variants with ---.
    Guy :: struct {
        using joost: union { // @compiler It would be nice if we could add a tag to anonymous using unions
            banana: void;
            apple: struct { a: u8; b: string;} = ---;
            orange: string = ---;
        }; @UnionTag:mytag
        mytag: enum {
            BANANA;
            APPLE;
            ORANGE;
        };
    }
    ok=, apple := Toml.deserialize("apple = {a = 32, b = 'Y'}", Guy); assert(ok);
    print("struct_apple: %\n", apple);
    print("struct_apple: %: %\n", apple.mytag, apple.apple);
    ok_apple, toml_apple := Toml.serialize(apple); assert(ok_apple);
    log("struct_apple serialized:\n%", toml_apple);

    // If the TOML data does not contain a field that is present in the struct, the field will be initialized to its default value.
    // Jai's initialization of unions is wack. So instead unions are initialized always initialized to the first variant.
    ok=, void_banana := Toml.deserialize("", Guy); assert(ok);
    print("void_banana: %\n", void_banana);
    print("void_banana: %: %\n", void_banana.mytag, void_banana.banana);

    // For convenience Toml.Value comes with an equality operator and copy procedure.
    ok=, left := Toml.deserialize("a.b = {c.d = 1}", Toml.Value); assert(ok);
    ok=, right := Toml.deserialize("a.b.c.d = 1", Toml.Value); assert(ok);
    assert(left == right);

    // Jai does not have commonly used types for dates and times. This module provides date/time types until the languages does.
    MyTime :: struct   { t: DateTimeOffset; }
    ok=, mytime := Toml.deserialize("t = 1979-05-27 07:32:00Z", MyTime); assert(ok);
    print("time: %\n", mytime);
    assert(mytime.t == DateTimeOffset.{date=Date.{year=1979, month=5, day=27}, time=Time.{hour=7, minute=32, second=0, millisecond=0}, offset_hour=0, offset_minute=0, offset_is_negative=false});

    MyChrono :: struct { t: Toml.DateTimeOffset; }
    ok=, mychrono := Toml.deserialize("t = 1979-05-27 07:32:00Z", MyChrono); assert(ok);
    using mychrono.t;
    print("chrono: %1-%2-%3 %4:%5:%6%7%8:%9\n", year, month, day, hour, minute, second, ifx offset_is_negative "-" else "+", offset_hour, offset_minute);

    // Due to differences in formatting dotted keys may become tables headers and vice versa.
    // Dotted key-values are always printed before table headers for correctness
    // This may reorder the keys in the serialized TOML data.
    ok=, header_order := Toml.deserialize("a.b = [1,2,3]\nc.d = 4", Toml.Value); assert(ok);
    ok_header, header := Toml.serialize(header_order); assert(ok_header);
    print("header_order:\n%", header);
    assert(header == "c.d=4\n[a]\nb=[1, 2, 3]\n");

    // Floats may be serialized from integer values in the TOML data.
    MyFloat :: struct { f: float; }
    ok=, myfloat := Toml.deserialize("f = 3", MyFloat); assert(ok);
    assert (myfloat.f == 3.0);

    // Pointers, ANY, VIEW and RESIZABLE arrays are supported at any depth in the struct definition.
    // These types that are referencing memory elsewhere will have new memory allocated for them with the context allocator.
    reference_types();

    // Success is returned as a boolean as the first return value. At this time there is no clear need to return an enum.
    // When an operation failed the error message can be found in the error log. If needed the error log can be captured as shown in this procedure.
    error_handling();
}

error_handling :: () {
    // To capture the error log without disturbing the normal logging behavior we can wrap the logger.
    Log_Wrap :: struct {
        logger: Logger;          // The original logger
        logger_data: *void;      // The original logger data
        capture: String_Builder; // The captured log
    }
    capture_log :: (message: string, data: *void, info: Log_Info) {
        // Log to the original logger
        wrap := cast(*Log_Wrap, data);
        wrap.logger(message, wrap.logger_data, info);

        // Log only error messages to the capture
        if info.common_flags & .ERROR {
            append(*wrap.capture, message);
            if message && message[message.count-1] != #char "\n"  append(*wrap.capture, "\n");
        }
    }

    wrap:= Log_Wrap.{context.logger, context.logger_data, .{}};                          // Store the current logger in the wrap
    Invalid :: struct { nullptr_array:[1]*void; }                                        // Invalid struct for which we know an error will be given
    inv_ok := Toml.serialize(Invalid.{.[null]},, logger=capture_log, logger_data=*wrap); // Call to serialize with the invalid struct and setting the context to the wrapped logger
    if !inv_ok print("capture_log: %", builder_to_string(*wrap.capture));                // The operation failed and the error message is captured in the wrap
    else assert(false);
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
    ok, pointers_toml := Toml.deserialize("p_s16 = 36\np_inner = {str = 'Barry'}", Outer); assert(ok);
    print("pointers_toml: %\n", pointers_toml);
    print("pointers_toml.p_s16: %\n",   pointers_toml.p_s16.*  );
    print("pointers_toml.p_inner: %\n", pointers_toml.p_inner.*);

    Getal :: #type,distinct u8;

    // Pointer to fixed array with initializer
    Vingt :: struct       {
        number : s8=20;
        getal: Getal= 23;
    }
    Fixed_Array :: struct {
        p_quatre: *[4]Vingt;
    }
    ok=, quatre_vingt := Toml.deserialize("p_quatre = [{getal = 9}, {getal = 4}, {number = 3}, {}]", Fixed_Array); assert(ok);
    log("quatre_vingt: %\n", quatre_vingt.p_quatre.*);
    assert(quatre_vingt.p_quatre.*[0].number == 20);
    assert(quatre_vingt.p_quatre.*[2].getal == 23);

    // Pointer to variant
    DefaultStruct :: struct {
        a: string="Anton";
        b: s8;
    }
    DefaultVariant :: #type,distinct DefaultStruct;
    MyVar :: struct {
        p_variant: *DefaultVariant;
    }
    ok=, mutant := Toml.deserialize("p_variant.b = 3", MyVar); assert(ok);
    print("mutant: %\n", mutant.p_variant.*);
    assert(mutant.p_variant.a == "Anton");

    // Pointer to struct with using (no impl required)
    MyUsing :: struct {
        using a: Vingt;
    }
    MyPtrUsing :: struct {
        p_using: *MyUsing;
    }
    ok=, use20 := Toml.deserialize("[p_using]\nnumber = 6", MyPtrUsing); assert(ok);
    print("use20: %\n", use20.p_using.*);
    assert(use20.p_using.getal == 23);

    // Union with first having an initializer
    MyUnionStruct :: struct {
        tag : enum {
            FIRST;
            SECOND;
        }
        union {
            first: Vingt;
            second: string = ---;
        }
    }
    ok=, un := Toml.deserialize("", MyUnionStruct); assert(ok);
    print("un: %\n", un.first);
    assert(un.first.number == 20);
    assert(un.first.getal == 23);

    // Pointer to union
    MyUnionPtr :: struct {
        p_union: *MyUnionStruct;
    }
    ok=, un_ptr := Toml.deserialize("tag = 'FIRST' \n p_union.first.number = 3", MyUnionPtr); assert(ok);
    print("un_ptr: %: %\n", un_ptr.p_union.tag, un_ptr.p_union.first);
    assert(un_ptr.p_union.first.number == 3);
    assert(un_ptr.p_union.first.getal == 23);

    // ARRAY VIEW
    Array_View :: struct {
        ocean: []s16;
    }
    ok=, arrayview_toml := Toml.deserialize("ocean = [1, 2, 3]", Array_View); assert(ok);
    print("arrayview_toml: %\n", arrayview_toml);
    assert(arrayview_toml.ocean[2] == 3);

    // ANY
    Amy :: struct {
        andy: Any;
    }
    ok=, toml4 := Toml.deserialize("andy = 3", Amy); assert(ok);
    print("toml4: %\n", toml4);
    assert("{3}" == tprint("%", toml4));
    ok=, toml4 = Toml.deserialize("andy = 'hello'", Amy); assert(ok);
    assert("{\"hello\"}" == tprint("%", toml4));
    ok=, toml4 = Toml.deserialize("andy = 3.3", Amy); assert(ok);
    assert("{3.3}" == tprint("%", toml4));
    ok=, toml4 = Toml.deserialize("andy = true", Amy); assert(ok);
    assert("{true}" == tprint("%", toml4));
    ok=, toml4 = Toml.deserialize("andy = [1, 7, 3]", Amy); assert(ok);
    assert("{[1, 7, 3]}" == tprint("%", toml4));
    ok=, toml4 = Toml.deserialize("andy = [1, 'd', 3]", Amy); assert(ok);
    print("%\n", toml4);

    AnyAndy :: struct {
        any_andy: s16;
        any_amy: s16;
    }
    OtherAndy :: struct {
        other_andy: string;
        other_amy: string;
    }
    ok=, toml5 := Toml.deserialize("[[andy]]\nany_andy = 9\nany_amy = 8\n[[andy]]\nother_andy = 'Peter'\nother_amy = 'Derick'", Amy); assert(ok);
    andies := cast(*[]Toml.Value, toml5.andy.value_pointer);
    ok=, any_andy := Toml.deserialize(andies.*[0], AnyAndy); assert(ok);
    assert("{9, 8}" == tprint("%", any_andy));
    ok=, other_andy := Toml.deserialize(andies.*[1], OtherAndy); assert(ok);
    assert("{\"Peter\", \"Derick\"}" == tprint("%", other_andy));
}

using Toml :: #import, file "../module.jai";
#import "Basic";
#import "File";
