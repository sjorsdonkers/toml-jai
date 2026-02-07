main :: () {
    // All run-time types are supported, excepts for serializing untagged unions. Unions are supported by tagging them.
    // Tagged union use the member_name as key (not the enum value's name), if the member is anonymous its index number is used.
    enum_unions();
    // For enumm and integer union that are explicitly bound, there is an artificial limitation limiting the values to the s64 range.
    // (This restriction is not artificial for those that are not bound, as we need the integer will be used to index in the struct members).
    integer_union();
    type_union();
    // #overlay members are not serialized only the primary members which they overlay
    overlays();
}


enum_unions :: () {
    // Jai's initialization of unions is wack. So it is highly recommended to use --- to disable initialization of all variants that do not correspond to the default tag.
    Guy :: struct {
        using scared: union mytag: enum {
            BANANA;
            APPLE;
            ORANGE;
        }= .ORANGE {
            .BANANA,, banana: *s64                        = ---;
            .APPLE,,  apple:  struct { a: u8; b: string;} = ---;
            .ORANGE,, orange: string="default";
        } @TomlOptional
    }
    ok, apple := Toml.string_to_type("scared.apple = {a = 32, b = 'Y'}", Guy); assert(ok);
    print("struct_apple: %\n", apple);
    print("struct_apple: %: %\n", apple.mytag, apple.apple);
    ok_apple, toml_apple := Toml.type_to_string(apple); assert(ok_apple);
    assert("scared.apple={a=32, b=\"Y\"}\n" == toml_apple, "%", toml_apple);
    // If the TOML data does not contain a field that is present in the struct, the field will be initialized to its default value.
    ok=, void_orange := Toml.string_to_type("", Guy); assert(ok);
    assert(void_orange.mytag == .ORANGE, "%", void_orange.mytag);
    assert(void_orange.orange == "default", "%", void_orange.orange);

    // Serializing Tagged Unions to null pointers/anys is supported with the NULL_STRING module parameter.
    null_banana := Guy.{mytag=.BANANA, banana=null};
    ok=, sum_null := Toml.type_to_string(null_banana); assert(ok);
    assert("scared.banana=\"~null~\"\n" == sum_null, "%", sum_null);

    // Tagged Unions can be nested without issue.
    Tags :: enum s8 {
        FIRST;
        SECOND;
        THIRD :: -33;
    };
    Group :: union tag: Tags {
            first:          string;
            second:         Guy = ---; // For consistency the enum value name is never used as key
            .THIRD,, third: Guy = ---;
    }

    group:= Group.{tag=.SECOND, second=Guy.{mytag=.ORANGE, orange="color"}};
    ok=, group_toml := Toml.type_to_string(group); assert(ok);
    assert("second.scared.orange=\"color\"\n" == group_toml);
    ok, group = Toml.string_to_type("third.scared.banana = -17", Group); assert(ok);
    assert(group.tag == .THIRD && group.third.mytag == .BANANA && group.third.banana.* == -17);

    // Note that just like normal structs if the member is anonymous it still requires the empty key "" in the TOML data.
    StructMember :: struct  {
        named: Guy;
        union tag: enum { A; B; } {
            .A,, a: string;
            .B,, b: Guy = ---;
        };
    }
    smem:= StructMember.{
        named=Guy.{mytag=.APPLE, apple=.{a=9, b="butter"}},
        tag=.B, b=Guy.{mytag=.ORANGE, orange="kleur"}
    };
    ok=, smem_toml:= Toml.type_to_string(smem); assert(ok);
    assert(#string DONE
named.scared.apple={a=9, b="butter"}
"".b.scared.orange="kleur"
DONE == smem_toml, "%", smem_toml);

    ok, smem = Toml.string_to_type(#string DONE
named.scared.banana = 987
"".b.scared.apple = {a = 3, b = 'peanut'}
DONE, StructMember); assert(ok);
    assert(smem.named.mytag == .BANANA && smem.named.banana.* == 987);
    assert(smem.tag == .B && smem.b.mytag == .APPLE && smem.b.apple.a == 3 && smem.b.apple.b == "peanut");

    // Tagged union use the member_name as key (not the enum value's name), if the member is anonymous it cannot be used (unless a modified Type_Info is used)
    // (de)serializing anonymous members is explicitly forbidden, as serializing would seem to work for a "" key, but it may surprisingly deserialize to another anonymous member
    // member_index base is not done by default due to the added complexity and processing for all normal cases
    // index based serialization can be realized by modifying the Type_Info
    // Has_Anonymous_Member :: union kind: Tags {
    //     struct { q: u8; };
    //     struct { t: string = ---; };
    // }
    // has_anon := Has_Anonymous_Member.{kind=.FIRST, q=42};
    // ok=, has_anon_toml := Toml.type_to_string(has_anon); assert(ok);
    // ok, has_anon = Toml.string_to_type("1.t = \"hello\"", Has_Anonymous_Member); assert(ok);
}
integer_union :: () {
    S8_Union :: union kind:s8= 4 {
        4,, a: u8;
        b: string          = ---;
        struct { t: string = ---; };
        -12,, c: s16       = ---;
    }
    s8_union := S8_Union.{kind=4, a=42};
    ok, s8_union_toml := Toml.type_to_string(s8_union); assert(ok);
    assert("a=42\n" == s8_union_toml, "%", s8_union_toml);

    // // If no integer is explicitly bound to member then the member index is used as value, starting from 0. So in this case a=0, b=1
    ok, s8_union = Toml.string_to_type("b=\"balloon\"", S8_Union); assert(ok);
    assert(s8_union.kind == 1 && s8_union.b == "balloon", "%", s8_union);

    // (de)serializing anonymous members is explicitly forbidden, as serializing would seem to work for a "" key, but it may surprisingly deserialize to another anonymous member
    // member_index base is not done by default due to the added complexity and processing for all normal cases
    // index based serialization can be realized by modifying the Type_Info
    // ok=, anonymous_2 := Toml.string_to_type("2.t=\"test\"", S8_Union); assert(ok);
    // ok=, anonymous_2_toml := Toml.type_to_string(anonymous_2); assert(ok);

    // Negative integers are supported as well, in this case c=-12
    ok=, c := Toml.string_to_type("c=-33", S8_Union); assert(ok);
    assert(c.kind == -12 && c.c == -33, "%", c);
}

type_union :: () {
    Type_Union :: union kind:Type=u16 {
        a: u8  = ---;
        b: u16;
    }

    type_union := Type_Union.{kind=u16, b=(300).(u16)};
    ok, type_union_toml := Toml.type_to_string(type_union); assert(ok);
    assert("b=300\n" == type_union_toml, "%", type_union_toml);

    ok, type_union = Toml.string_to_type("a=40", Type_Union); assert(ok);
    assert(type_union.kind == u8 && type_union.a == 40, "%", type_union);
}

overlays :: () {
    // #overlay members are not serialized, as the data they represent is already printed by the primary members which they overlay
    // This also means the primary members should always be in a valid state, pointer members must point to data matching the type
    My_Overlay :: struct {
        a: u8; b: u8; c: u8; d: u8;
        #overlay (a) abcd: u32;
    }
    my_overlay := My_Overlay.{abcd=4346721};
    ok, overlay_toml := Toml.type_to_string(my_overlay); assert(ok);
    assert("a=97\nb=83\nc=66\nd=0\n" == overlay_toml, "%", overlay_toml);
    // #overlay fields are optional and not recommended in the toml string
    ok=, overlay_data := Toml.string_to_type("a=1\nb=2\nc=3\nd=4", My_Overlay); assert(ok); // abcd is omitted
    assert(overlay_data.a == 1
        && overlay_data.b == 2
        && overlay_data.c == 3
        && overlay_data.d == 4
        && overlay_data.abcd == 67305985, "%", overlay_data.abcd);
    // #overlay fields may be provided in the toml, the data is overwritten on top of each other in the order of the members in the struct
    ok, overlay_data = Toml.string_to_type("a=3\nb=3\nc=3\nd=3\nabcd=4346721", My_Overlay); assert(ok);
    assert(overlay_data.a == 97
        && overlay_data.b == 83
        && overlay_data.c == 66
        && overlay_data.d == 0
        && overlay_data.abcd == 4346721);
}

using Toml :: #import, file "../module.jai";
#import "Basic";
