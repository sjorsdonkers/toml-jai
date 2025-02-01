

enum_as_int :: () {
    Paprika :: enum { GREEN; ORANGE; RED; }
    Basket :: struct {
        paprika: Paprika;
        everything_else: u8;
    }

    custom_enum_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
        if info.type != .ENUM return false;
        enum_value := Reflection.get_enum_value(slot, xx info);
        ok, value  := Toml.type_to_value(*enum_value, type_info(s64));
        return true, ok, value;
    }

    basket := Basket.{paprika=.ORANGE, everything_else=42};
    ok1, toml1 := Toml.serialize(basket);                                                    assert(ok1);
    ok2, toml2 := Toml.serialize(basket,, toml_custom_type_to_value = custom_enum_to_value); assert(ok2);
    assert(toml1 == "paprika=\"ORANGE\"\neverything_else=42\n", "%", toml1);
    assert(toml2 == "paprika=1\neverything_else=42\n", "%", toml2);

    // Deserialize with custom value_to_type

    custom_value_to_enum :: (toml: Value, slot: *void, info: *Type_Info, parent_name:string, name:string) -> done:=true, ok:=false {
        if info.type != .ENUM return false;
        expect(toml.type, .INT, parent_name, name);
        enum_info :*Type_Info_Enum = xx info;

        found := array_find(enum_info.values, toml.int_value);
        if !found { log_error("Value % is not a variant of enum %", toml.int_value, enum_info.name); return; }
        Reflection.set_enum_value(slot, enum_info, toml.int_value);
        return true, true;
    }

    ok3, basket3 := Toml.deserialize("paprika=\"RED\"\neverything_else=3\n", Basket);                                              assert(ok3);
    ok4, basket4 := Toml.deserialize("paprika=2\neverything_else=3\n", Basket,, toml_custom_value_to_type = custom_value_to_enum); assert(ok4);
    assert(basket3.paprika == .RED && basket3.everything_else == 3, "%", basket3);
    assert(basket4.paprika == .RED && basket4.everything_else == 3, "%", basket3);
}

member_modifications :: () {
    ThreeNamed :: struct {
        a: u8;
        b: u8;
        c: u8;
    }

    two_renamed_type_info :: () -> Type_Info_Struct {
        renamed_info := type_info(ThreeNamed).*;
        renamed_info.members = array_copy(renamed_info.members); // Note: temp not needed as all memory will be on a context allocator as is required by the Toml interface.
        renamed_info.members[0].name = "alpha";
        renamed_info.members[2].name = "gamma";
        array_unordered_remove_by_index(*renamed_info.members, 1);
        return renamed_info;
    }
    custom_modified_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
        if info != type_info(ThreeNamed) return false;
        modified_info := two_renamed_type_info();
        ok, value := Toml.type_to_value(slot, *modified_info);
        return true, ok, value;
    }
    custom_value_to_modified :: (toml: Value, slot: *void, info: *Type_Info, parent_name:string, name:string) -> done:=true, ok:=false {
        if info != type_info(ThreeNamed) return false;
        modified_info := two_renamed_type_info();
        ok := Toml.value_to_type(toml, slot, *modified_info, parent_name, name);
        return true, ok;
    }

    three_named := ThreeNamed.{a=1, b=2, c=3};
    ok1, toml1 := Toml.serialize(three_named);                                                        assert(ok1);
    ok2, toml2 := Toml.serialize(three_named,, toml_custom_type_to_value = custom_modified_to_value); assert(ok2);
    assert(toml1 == "a=1\nb=2\nc=3\n", "%", toml1);
    assert(toml2 == "alpha=1\ngamma=3\n", "%", toml2);

    ok3, three_named3 := Toml.deserialize("a=4\nb=5\nc=6\n", ThreeNamed);                                                           assert(ok3);
    ok4, three_named4 := Toml.deserialize("alpha=4\ngamma=6\n", ThreeNamed,, toml_custom_value_to_type = custom_value_to_modified); assert(ok4);
    assert(three_named3.a == 4 && three_named3.b == 5 && three_named3.c == 6, "%", three_named3);
    assert(three_named4.a == 4 && three_named4.b == 0 && three_named4.c == 6, "%", three_named4);
}

arbitrary_magic :: () {
    new_context := context;
    // Serialize with custom type_to_value
    new_context.toml_custom_type_to_value = custom_magic_to_value;

    push_context new_context {
        magic := Magic_Bytes.{.[0x00, 0x43, 0xf2]}; // Assumes little_endian
        ok, toml  := Toml.serialize(magic); assert(ok);
        assert(toml == "flag=\"A\"\nsigned=-3517\n", "%", toml);

        magic.bytes[0] = 0x01;
        ok, toml = Toml.serialize(magic); assert(ok);
        assert(toml == "unaltered=[1, 67, 242]\n", "%", toml);

        magic.bytes[0] = 0x02;
        ok = Toml.serialize(magic); assert(!ok);
    }

    // Deserialize with custom value_to_type
    new_context.toml_custom_value_to_type = custom_value_to_magic;

    push_context new_context {
        ok, magic := Toml.deserialize("flag=\"A\"\nsigned=-3517\n", Magic_Bytes); assert(ok);
        assert(magic.bytes[0] == 0x00 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

        ok, magic = Toml.deserialize("unaltered=[1, 67, 242]\n", Magic_Bytes); assert(ok);
        assert(magic.bytes[0] == 0x01 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

        ok = Toml.deserialize("unaltered=[2, 67, 242, 0]\n", Magic_Bytes); assert(!ok);
    }
}

Magic_Bytes :: struct {
    bytes : [3]u8;
};
custom_magic_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    if info != type_info(Magic_Bytes) return false;

    ret: Toml.Value; // Defaults inits to Table
    if slot.(*u8).* == {
    case 0;
        ok, flag    := Toml.type_to_value(*"A", type_info(string)); if !ok return;
        ok=, signed := Toml.type_to_value(slot+1, type_info(s16)); if !ok return;
        array_add(*ret.table, .{key="flag", value=flag}, .{key="signed", value=signed});
    case 1;
        ok, array := Toml.type_to_value(slot, type_info([3]u8)); if !ok return;
        array_add(*ret.table, .{key="unaltered", value=array});
    case;
        log_error("Invalid Magic_Bytes: %", slot.(*Magic_Bytes).*);
        return;
    }
    return true, true, ret;
}
custom_value_to_magic :: (toml: Value, slot: *void, info: *Type_Info, parent_name:string, name:string) -> done:=true, ok:=false {
    if info != type_info(Magic_Bytes) return false;

    if toml.type != .TABLE { log_error("Expected table for Magic_Bytes, got %", toml.type); return; }
    if toml.table.count == {
    case 2;
        if toml.table[0].key != "flag"   { log_error("Expected key 'flag' for Magic_Bytes, got %",   toml.table[0].key); return; }
        if toml.table[1].key != "signed" { log_error("Expected key 'signed' for Magic_Bytes, got %", toml.table[1].key); return; }


        Flag :: enum u8 { A :: 0; }
        ok := Toml.value_to_type(toml.table[0].value, slot, type_info(Flag), name, "flag"); if !ok return;
        ok = Toml.value_to_type(toml.table[1].value, slot+1, type_info(s16), name, "signed");
        return true, ok;
    case 1;
        if toml.table[0].key != "unaltered" { log_error("Expected key 'unaltered' for Magic_Bytes, got %", toml.table[0].key); return; }
        ok := Toml.value_to_type(toml.table[0].value, slot, type_info([3]u8), name, "unaltered"); if !ok return;
        if slot.(*Magic_Bytes).bytes[0] != 0x01 {
            log_error("Expected 0x01 for unaltered Magic_Bytes, got %", slot.(*Magic_Bytes).bytes[0]);
            return;
        }
        log("Magic_Bytes unaltered: %", slot.(*Magic_Bytes).bytes);
        return true, ok;
    }
    log_error("Expected 1 or 2 keys for Magic_Bytes, got %", toml.table.count);
    return;
}

main :: () {
    enum_as_int();
    member_modifications();
    arbitrary_magic();
}

using Toml :: #import, file "../module.jai"(CUSTOM_HANDLERS=true);
#import "Basic";
Reflection :: #import "Reflection";
