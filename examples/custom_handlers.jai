
// By default this Toml modules makes several choices like, enums as string, members serialized by their name, no members omitted, etc.
// These choices may be fine for the large majority of use-cases but not all. Custom handlers enable the user to modify the serialization/deserialization of types.
// Custom handlers have several design goals:
// - Keep the core Toml module implementation clean from complexity.
// - Enable custom serialization of types we do not own (external Modules) as we may not be able to add notes or remove members.
// - The same type should be serializable in different ways defined at the procedure call site, not struct definition.
// - Enable data tweaks during serialization as opposed to full copies of nested structure trees (separate structs for serialization and use within the application).
//
// Note that these custom handler drive "what" is (de)serialized, they do not help with formatting of the toml.

// By default custom handler support is not compiled. We need to import the module with CUSTOM_HANDLERS=true to enable it.
//
// #import "Toml"(CUSTOM_HANDLERS=true);
//
// This will add 2 procedure members to the context:
// - toml_custom_type_to_value := (slot: *void, info: *Type_Info) -> done:bool, ok:bool, toml:Value;
// - toml_custom_value_to_type := (toml: Value, slot: *void, info:*Type_Info, parent_name:string, name:string) -> done:bool, ok:bool;

main :: () {
    enum_as_int();
    member_modifications();
    arbitrary_magic_binary_encoding();
    error_on_superfluous_keys();
}

enum_as_int :: () {
    // By default enums are serialized as strings. We can change this to serialize them as their integer value.
    Paprika :: enum { GREEN; ORANGE; RED; }
    Basket :: struct {
        paprika: Paprika;
        everything_else: u8;
    }

    // The user writes a procedure to handle the serialization of the enum
    // from the data stored in slot and returns a Toml Value.
    custom_enum_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
        if info.type != .ENUM return false; // Alternatively we could check specifically for `info != type_info(Paprika)`
        enum_value := Reflection.get_enum_value(slot, xx info);
        ok, value  := Toml.type_to_value(*enum_value, type_info(s64));
        return true, ok, value; // By returning done=true we signal that the returned value should be used and to skip default serialization.
    }

    // The user can then choose to set the custom handler at the call site.
    // If it is not set the default handler will be used serializing the enum as a string.
    // By setting the custom handler in the context enums are serialized as integers.
    basket := Basket.{paprika=.ORANGE, everything_else=42};
    ok_default, toml_default := Toml.serialize(basket);                                                    assert(ok_default);
    ok_custom,  toml_custom  := Toml.serialize(basket,, toml_custom_type_to_value = custom_enum_to_value); assert(ok_custom);
    assert(toml_default == "paprika=\"ORANGE\"\neverything_else=42\n", "%", toml_default);
    assert(toml_custom  == "paprika=1\neverything_else=42\n",          "%", toml_custom );

    // For deserialization it works the same way, but in opposite direction.
    // The custom procedure receives a Toml Value and writes into the slot.
    custom_value_to_enum :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
        if info.type != .ENUM return false;
        expect(toml.type, .INT, parent_name, name);
        enum_info :*Type_Info_Enum = xx info;

        found := array_find(enum_info.values, toml.int_value);
        if !found { log_error("Value % is not a variant of enum %", toml.int_value, enum_info.name); return; }
        Reflection.set_enum_value(slot, enum_info, toml.int_value);
        return true, true;
    }

    // The user can again opt in to using the custom handler at the call site, by setting it in the context.
    ok3, basket3 := Toml.deserialize("paprika=\"RED\"\neverything_else=3\n", Basket);                                              assert(ok3);
    ok4, basket4 := Toml.deserialize("paprika=2\neverything_else=3\n", Basket,, toml_custom_value_to_type = custom_value_to_enum); assert(ok4);
    assert(basket3.paprika == .RED && basket3.everything_else == 3, "%", basket3);
    assert(basket4.paprika == .RED && basket4.everything_else == 3, "%", basket3);
}

member_modifications :: () {
    // The custom handlers for modifications to members like omitting, renaming, reordering work in a similar way.
    // In general the trick is to create a new Type_Info with the desired modifications and then use the default serialization/deserialization.
    // Note that often the simplest way to create a new Type_Info is by defining a new Type. When doing so
    // be careful that the member offset_in_bytes is correct with respect to the original Type_Info.
    // In this example we instead make a copy of the original Type_Info and modify it.
    // We still need to be careful not to modify the original Type_info as the it needs to be a shallow copy (for custom handlers with pointers to sub-type_infos).
    ThreeNamed :: struct {
        a: u8;
        b: u8;
        c: u8;
    }

    two_renamed_type_info :: () -> Type_Info_Struct {
        renamed_info := type_info(ThreeNamed).*;
        renamed_info.members = array_copy(renamed_info.members); // Note: temp not needed as all memory will be on a context allocator as is required by the Toml Module interface.
        renamed_info.members[0].name = "alpha"; // Rename
        renamed_info.members[2].name = "gamma";
        array_unordered_remove_by_index(*renamed_info.members, 1); // Omit
        return renamed_info;
    }
    custom_modified_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
        if info != type_info(ThreeNamed) return false; // Use default serialization for everything else by returning done=false.
        modified_info := two_renamed_type_info();
        ok, value := Toml.type_to_value(slot, *modified_info);
        return true, ok, value;
    }
    custom_value_to_modified :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
        if info != type_info(ThreeNamed) return false;
        modified_info := two_renamed_type_info();
        ok := Toml.value_to_type(toml, slot, *modified_info, parent_name, name);
        return true, ok;
    }

    // When serializing with the custom handler, the members are renamed and the middle member is omitted.
    three_named := ThreeNamed.{a=1, b=2, c=3};
    ok1, toml1 := Toml.serialize(three_named);                                                        assert(ok1);
    ok2, toml2 := Toml.serialize(three_named,, toml_custom_type_to_value = custom_modified_to_value); assert(ok2);
    assert(toml1 == "a=1\nb=2\nc=3\n", "%", toml1);
    assert(toml2 == "alpha=1\ngamma=3\n", "%", toml2);

    // Similarly, when deserializing with the custom handler, the members are renamed and the middle member is omitted.
    // Note that we do not fail on the missing member as it is default initialized (in this case to 0).
    ok3, three_named3 := Toml.deserialize("a=4\nb=5\nc=6\n", ThreeNamed);                                                           assert(ok3);
    ok4, three_named4 := Toml.deserialize("alpha=4\ngamma=6\n", ThreeNamed,, toml_custom_value_to_type = custom_value_to_modified); assert(ok4);
    assert(three_named3.a == 4 && three_named3.b == 5 && three_named3.c == 6, "%", three_named3);
    assert(three_named4.a == 4 && three_named4.b == 0 && three_named4.c == 6, "%", three_named4);
}

arbitrary_magic_binary_encoding :: () {
    // The custom handlers enable us to do conversions of arbitrary complexity during serialization/deserialization.
    // In this example we show how data in a binary encoding can be serialized to Toml and back.
    // Remember that this binary blob could be at any part of a struct hierarchy,
    // still we do not need to decode the blob before serialization. As we convert it when we encounter it.

    // Serialize a binary encoding with custom type_to_value
    new_context := context; // A different way to set the context custom handlers for multiple calls
    new_context.toml_custom_type_to_value = custom_magic_to_value;

    push_context new_context {
        // Depending on the first byte we serialize the data differently.
        magic := Magic_Bytes.{.[0x00, 0x43, 0xf2]}; // Assumes little_endian
        ok, toml  := Toml.serialize(magic); assert(ok);
        assert(toml == "flag=\"A\"\nsigned=-3517\n", "%", toml);

        magic.bytes[0] = 0x01;
        ok, toml = Toml.serialize(magic); assert(ok);
        assert(toml == "unaltered=[1, 67, 242]\n", "%", toml);

        // In a custom handler we can also check for invalid data and return done=true, ok=false which will propagate up.
        magic.bytes[0] = 0x02;
        ok = Toml.serialize(magic); assert(!ok);
    }

    // Deserialize to the binary encoding with custom value_to_type
    new_context.toml_custom_value_to_type = custom_value_to_magic;

    push_context new_context {
        // When deserializing the data is converted back to the binary encoding from different looking Toml data.
        ok, magic := Toml.deserialize("flag=\"A\"\nsigned=-3517\n", Magic_Bytes); assert(ok);
        assert(magic.bytes[0] == 0x00 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

        ok, magic = Toml.deserialize("unaltered=[1, 67, 242]\n", Magic_Bytes); assert(ok);
        assert(magic.bytes[0] == 0x01 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

        // Error propagation works the same way as with custom type_to_value.
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
custom_value_to_magic :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
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

error_on_superfluous_keys :: () {
    // By default the Toml module ignores superfluous keys in a table.
    // We can use a custom handler to error on superfluous keys.
    catch_superfluous_keys :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
        if info.type != .STRUCT || toml.type != .TABLE return false;
        struct_info :*Type_Info_Struct = xx info;
        if array_find(struct_info.notes, "SumType") return false; // SumTypes never allow superfluous fields

        remaining_members := array_copy(struct_info.members); defer array_free(remaining_members);
        for keyvalue: toml.table {
            for member: remaining_members {
                if member.flags & (.CONSTANT |.IMPORTED) remove;
                if keyvalue.key == member.name {
                    array_unordered_remove_by_index(*remaining_members, it_index);
                    continue keyvalue;
                }
            }
            log_error("Superfluous key `%` in %.%", keyvalue.key, parent_name, name);
            return true, false; // We are done, we found an error
        }
        return false; // We are not done since we are only validating here, the Value still needs to be deserialized
    }

    OnlyA :: struct {
        a: u8;
    }
    ok := Toml.deserialize("a=1 \n b=2", OnlyA); assert(ok);
    ok  = Toml.deserialize("a=1 \n b=2", OnlyA,, toml_custom_value_to_type = catch_superfluous_keys); assert(!ok);

}

using Toml :: #import, file "../module.jai"(CUSTOM_HANDLERS=true);
#import "Basic";
Reflection :: #import "Reflection";
