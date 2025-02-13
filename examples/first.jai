main :: () {
    // TOML data is not expected to multi-GB, so just read the entire file. For easy cleanup of the memory allocated for
    // the returned structs we can push an allocator. The type Toml.Value can be used deserialization target for any TOML data.
    contents := read_entire_file("data/inline_table.toml");
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    ok, toml_value := Toml.deserialize(contents, Toml.Value,, allocator=heap); assert(ok);
    ok_toml, toml := Toml.serialize(toml_value,, allocator=heap); assert(ok_toml);
    print("%\n", toml);

    // We can also deserialize the TOML data into a struct. The struct must have the same fields as the TOML data.
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
    assert("{false, 23.299999, {32, \"Y\", Y}, [{2}, {-3}, {4}], \"Mai\"}" == tprint("%", my_struct), "%", my_struct);
    ok=, as_value := Toml.serialize(my_struct); assert(ok);
    print("%\n", as_value);

    // By default all members are required to be present in the TOML. @TomlOptional or a custom handler can be used to make them optional or ignored.
    optionals();

    // When struct or pointer members of a struct are declared with `using` the member name are required in the TOML data.
    // If the member is anonymous the member name is an empty string "".
    using_members();

    // All run-time types are supported, excepts for serializing untagged unions. Unions are supported by tagging them.
    unions_and_place();

    // For convenience Toml.Value comes with an equality operator and copy procedure.
    ok=, left := Toml.deserialize("a.b = {c.d = 1}", Toml.Value); assert(ok);
    ok=, right := Toml.deserialize("a.b.c.d = 1", Toml.Value); assert(ok);
    assert(left == copy(right));

    // Jai Apollo_time.Calendar_Time is not usable for TOML dates/times. This module provides date/time types until the languages does.
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

optionals :: () {
    // If the TOML data does not contain a field that is present in the struct deserialize will fail.
    Required :: struct { blob : u8; }
    ok := Toml.deserialize("", Required); assert(!ok);

    // To always keep a member at the default value thus prevent attempting to read a field at all,
    // even if it is present we can remove it from the Type_Info, see custom_handlers.jai,

    // If however we to allow a field to be missing, but read it if it is present the member can be annotated with @TomlOptional
    // The default value will be used if the field is missing.
    Optionals :: struct {
        a: u8 = 17; @TomlOptional // @TomlOptional may be removed in the future in favor of a convenience procedure to use in a custom handler.
        b: u8 = 18; @TomlOptional
    }
    ok=, optionals := Toml.deserialize("a=99", Optionals); assert(ok);
    assert(optionals.a == 99 && optionals.b == 18, "%", optionals);
}

using_members :: () {
    // When a named member is declared `using` the member name is still required.
    Named_Using :: struct {
        using hi: struct { q: u8; };
    }
    ok, named_using1:= Toml.deserialize("hi = { q=98 }", Named_Using); assert(ok);
    assert(named_using1.hi.q == 98, "%", named_using1.hi.q);
    // When a struct members is declared with `using` the member name cannot be omitted in the TOML to set the data
    // This is to prevent having multiple ways to define the same data. It also reduced the amount of recursion we have to do when deserializing.
    ok = Toml.deserialize("q = 99", Named_Using); assert(!ok);
    // When serializing a using member it will also write the member name.
    ok=, named_using_str := Toml.serialize(named_using1); assert(ok);
    assert(named_using_str == "hi.q=98\n", "%", named_using_str);

    // A pointer member that is declared `using` is the same.
    Q :: struct {
        q: s16;
    }
    Pointer_Using :: struct {
        using hi: *Q;
    }
    ok=, pointer_using := Toml.deserialize("hi = { q=97 }", Pointer_Using); assert(ok);
    assert(pointer_using.hi.q == 97, "%", pointer_using.hi.q);
    // When serializing a pointer member it will not omit the member name, consistent with deserialization.
    ok=, pointer_using_str := Toml.serialize(pointer_using); assert(ok);
    assert(pointer_using_str == "hi.q=97\n");

    // An anonymous member that is declared `using` still require the empty key "" in the TOML data.
    // The members however are clustered together into a single table.
    Anonymous_Using :: struct {
        struct { q: u8; };
        struct { t: string; };
    }
    ok=, anonymous_using:= Toml.deserialize("'' = { q = 96, t = 'hello' }", Anonymous_Using); assert(ok);
    assert(anonymous_using.q == 96, "%", anonymous_using.q);
    assert(anonymous_using.t == "hello", "%", anonymous_using.t);
    // When serializing an anonymous using member it will not omit the member name, consistent with deserialization.
    ok=, anonymous_using_str := Toml.serialize(anonymous_using); assert(ok);
    assert(anonymous_using_str == #string DONE
"".q=96
"".t="hello"
DONE, "%", anonymous_using_str);
}

unions_and_place :: () {
    // A struct with a @SumType is required to have the first member be the tag and the second be the union with the same number of members as the tag.
    // Jai's initialization of unions is wack. So it is highly recommended to use --- to disable initialization of all variants that do not correspond to the default tag.
    Guy :: struct {
        using scared: struct @SumType {
            mytag: enum {
                BANANA;
                APPLE;
                ORANGE;
            }= .ORANGE;
            union {
                banana: *s64 = ---;
                apple: struct { a: u8; b: string;} = ---;
                orange: string="default";
            };
        } @TomlOptional
    }
    ok, apple := Toml.deserialize("scared.APPLE = {a = 32, b = 'Y'}", Guy); assert(ok);
    print("struct_apple: %\n", apple);
    print("struct_apple: %: %\n", apple.mytag, apple.apple);
    ok_apple, toml_apple := Toml.serialize(apple); assert(ok_apple);
    assert("scared.APPLE={a=32, b=\"Y\"}\n" == toml_apple, "%", toml_apple);

    // If the TOML data does not contain a field that is present in the struct, the field will be initialized to its default value.
    ok=, void_orange := Toml.deserialize("", Guy); assert(ok);
    assert(void_orange.mytag == .ORANGE, "%", void_orange.mytag);
    assert(void_orange.orange == "default", "%", void_orange.orange);

    // Serializing SumTypes to null pointers/anys is supported with the NULL_STRING module parameter.
    null_banana := Guy.{mytag=.BANANA, banana=null};
    ok=, sum_null := Toml.serialize(null_banana); assert(ok);
    assert("scared.BANANA=\"~null~\"\n" == sum_null, "%", sum_null);

    // Sum-type can be nested without issue.
    Group :: struct @SumType {
        tag: enum {
            FIRST;
            SECOND;
            THIRD;
        }
        union {
            first: string;
            second: Guy;
            third: Guy;
        };
    }
    group:= Group.{tag=.SECOND, second=Guy.{mytag=.ORANGE, orange="color"}};
    ok=, group_toml := Toml.serialize(group); assert(ok);
    assert("SECOND.scared.ORANGE=\"color\"\n" == tprint("%", group_toml));
    ok, group = Toml.deserialize("THIRD.scared.BANANA = -17", Group); assert(ok);
    assert(group.tag == .THIRD && group.third.mytag == .BANANA && group.third.banana.* == -17);

    // Note that just like normal structs if the member is anonymous it still requires the empty key "" in the TOML data.
    StructMember :: struct  {
        named: Guy;
        struct @SumType {
            tag: enum { A; B; }
            union { a: string; b: Guy; };
        }
    }
    smem:= StructMember.{
        named=Guy.{mytag=.APPLE, apple=.{a=9, b="butter"}},
        tag=.B, b=Guy.{mytag=.ORANGE, orange="kleur"}
    };
    ok=, smem_toml:= Toml.serialize(smem); assert(ok);
    assert(#string DONE
named.scared.APPLE={a=9, b="butter"}
"".B.scared.ORANGE="kleur"
DONE == tprint("%", smem_toml), "%", smem_toml);

    ok, smem = Toml.deserialize(#string DONE
named.scared.BANANA = 987
"".B.scared.APPLE = {a = 3, b = 'peanut'}
DONE, StructMember); assert(ok);
    assert(smem.named.mytag == .BANANA && smem.named.banana.* == 987);
    assert(smem.tag == .B && smem.b.mytag == .APPLE && smem.b.apple.a == 3 && smem.b.apple.b == "peanut");

    // If a structure has overlapping members / members with different names through the #place directive
    // they are all serialized. This is inconsistent with Basic.print which skips members that overlap previous members.
    // Note that this may be unsafe if #place is used for a union use-case like a string overlapping some floats. In this case,
    // if the floats are "active" the string is still serialized assuming the data pointer is valid. -- Perhaps we should simply not allow #place.
    // When deserializing the last overlapping member in the struct definition that is also in the toml wins.
    // It is recommended to make #place members @TomlOptional such that they are not all required.
    #import "Math";
    has_hash_place:= Plane3.{3., 81., .18, .65};
    print("has_hash_place: %\n", has_hash_place);
    ok=, hash_toml:= Toml.serialize(has_hash_place); assert(ok);
    print("hash_toml: %\n", hash_toml);
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

    wrap:= Log_Wrap.{context.logger, context.logger_data, .{}};                               // Store the current logger in the wrap
    Invalid :: struct { e: enum{}; }                                                          // Struct for which we know we can make an error occur
    inv_ok := Toml.serialize(Invalid.{e=xx,force 9},, logger=capture_log, logger_data=*wrap); // Call to serialize with the invalid struct and setting the context to the wrapped logger
    if !inv_ok print("capture_log: %", builder_to_string(*wrap.capture));                     // The operation failed and the error message is captured in the wrap
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

    // Null pointer
    Null_Pointer :: struct {
        ptr: *string;
    }
    // ~null~ is the default string used to represent null values in the TOML data.
    ok=, null_ptr := Toml.deserialize("ptr = \"~null~\"", Null_Pointer); assert(ok);
    assert(null_ptr.ptr == null, "%", null_ptr);
    // We can change the string used to represent null values in the TOML data to any other Value.
    ok=, zero_ptr := Toml.deserialize("ptr = 17.0", Null_Pointer,, toml_null_value = Value.{type=.FLOAT, float_value=17.0}); assert(ok);
    assert(zero_ptr.ptr == null, "%", zero_ptr);
    // Serialization works the same way.
    ok=, nil_toml := Toml.serialize(Null_Pointer.{ptr=null},, toml_null_value = Value.{type=.STRING, string_value="nil"}); assert(ok);
    assert(nil_toml == "ptr=\"nil\"\n", "%", nil_toml);

    // Optional pointer
    My_Optional_Pointer :: struct {
        ptr: *u8; @TomlOptional
    }
    // Optional values are always serialized so it just uses the toml_null_value
    ok=, optional_toml := Toml.serialize(My_Optional_Pointer.{ptr=null}); assert(ok);
    assert(optional_toml == "ptr=\"~null~\"\n", "%", optional_toml);
    // Since the pointer is optional it deserializes to null if the field is missing.
    ok=, my_opt_ptr := Toml.deserialize("", My_Optional_Pointer); assert(ok);
    assert(my_opt_ptr.ptr == null, "%", my_opt_ptr);

    Getal :: #type,distinct u8;

    // Pointer to fixed array with initializer
    Vingt :: struct       {
        number : s8=20; @TomlOptional
        getal: Getal= 23; @TomlOptional
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
        a: string="Anton"; @TomlOptional
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
    ok=, use20 := Toml.deserialize("[p_using]\na.number = 6", MyPtrUsing); assert(ok);
    print("use20: %\n", use20.p_using.*);
    assert(use20.p_using.getal == 23);

    // Union with first having an initializer
    MyUnionStruct :: struct @SumType {
        tag : enum {
            FIRST;
            SECOND;
        }
        union {
            first: Vingt;
            second: string = ---;
        }
    }

    // Pointer to union
    MyUnionPtr :: struct {
        p_union: *MyUnionStruct;
    }
    ok=, un_ptr := Toml.deserialize("p_union.FIRST.number = 3", MyUnionPtr); assert(ok);
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

    // Array with null pointer
    Null_Array :: struct {
        array: []*s16;
    }
    five :s16= 5;
    ok=, null_array_toml := Toml.serialize(Null_Array.{array=.[*five, null]}); assert(ok);
    assert(null_array_toml == "array=[5, \"~null~\"]\n", "%", null_array_toml);
    ok=, null_array := Toml.deserialize("array = [5, \"~null~\"]", Null_Array); assert(ok);
    assert(null_array.array[1] == null, "%", null_array.array[1]);

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
    assert(toml4.andy.type.type == .ARRAY);
    array_info :*Type_Info_Array= xx toml4.andy.type;
    assert(array_info.element_type == type_info(Toml.Value));
    for cast(*[]Toml.Value, toml4.andy.value_pointer).* { assert(it.type == .INT); }
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
    ok=, any_andy := Toml.value_to_type(andies.*[0], AnyAndy); assert(ok);
    assert("{9, 8}" == tprint("%", any_andy));
    ok=, other_andy := Toml.value_to_type(andies.*[1], OtherAndy); assert(ok);
    assert("{\"Peter\", \"Derick\"}" == tprint("%", other_andy));

    // Null Any
    ok=, null_any_toml := Toml.serialize(Amy.{}); assert(ok);
    assert("andy=\"~null~\"\n" == null_any_toml, "%", null_any_toml);
    ok=, null_any := Toml.deserialize("andy = \"~null~\"", Amy); assert(ok);
    assert(null_any.andy.value_pointer == null, "%", null_any.andy.value_pointer);
}

using Toml :: #import, file "../module.jai";
#import "Basic";
#import "File";
