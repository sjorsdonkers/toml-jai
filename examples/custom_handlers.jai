
// By default this Toml modules makes several choices like, enums as string, members serialized by their name, no members omitted, etc.
// These choices may be fine for the large majority of use-cases but not all. Custom handlers enable the user to modify the serialization/deserialization of types.
// Custom handlers have several design goals:
// - Keep the core Toml module implementation clean from complexity.
// - Enable custom serialization of types we do not own (external Modules) as we may not be able to add notes or remove members.
// - The same type should be serializable in different ways defined at the procedure call site, not struct definition.
// - Enable data tweaks during serialization as opposed to full copies of nested structure trees (separate structs for serialization and use within the application).
// - The user should be able to opt-out of the default behavior of handling special types like Toml.Value, Chrono, and SumTypes. A user can opt-out by setting a procedure which is a no-op or any procedure that does not call the default_custom_handler.
//
// Note that these custom handler drive "what" is (de)serialized, they do not help with formatting of the toml.

// The Toml module adds 2 procedure members to the context:
// - toml_custom_type_to_value := (slot: *void, info: *Type_Info) -> done:bool, ok:bool, toml:Value;
// - toml_custom_value_to_type := (toml: Value, slot: *void, info:*Type_Info, parent_name:string, name:string) -> done:bool, ok:bool;

main :: () {
    enum_as_int();
    member_modifications();
    arbitrary_binary_encoding();
//     error_on_superfluous_keys();
    polymorphic_types_like_hashtable_support();
}

// The user writes a procedure to handle the serialization of the enum
// from the data stored in slot and returns a Toml Value.
custom_enum_to_value :: (data: $T, $info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    #if info.type != .ENUM return false; // Alternatively we could check specifically for `info != type_info(Paprika)`
    else {
        ok, value  := Toml_Enum.type_to_value_shared_memory(data.(s64), type_info(s64));
        return true, ok, value; // By returning done=true we signal that the returned value should be used and to skip default serialization.
    }
}
Toml_Enum :: #import, file "../module.jai"(CUSTOM_TYPE_TO_VALUE = #code custom_enum_to_value(data, info));
#poke_name Toml_Enum custom_enum_to_value;
using Toml_Enum.Data; // For convenience of writing types, these are compatible regardless of module parameters.

enum_as_int :: () {
    // By default enums are serialized as strings. We can change this to serialize them as their integer value.
    Paprika :: enum { GREEN; ORANGE; RED; }
    Basket :: struct {
        paprika: Paprika;
        everything_else: u8;
    }

    // The user can then choose to set the custom handler when importing the module
    // If it is not set the default handler will be used serializing the enum as a string.
    // By setting the custom handler in the context enums are serialized as integers.
    basket := Basket.{paprika=.ORANGE, everything_else=42};
    // ok_default, toml_default := Toml.serialize(basket); assert(ok_default);
    ok_custom,  toml_custom  := Toml_Enum.serialize(basket); assert(ok_custom);
    // assert(toml_default == "paprika=\"ORANGE\"\neverything_else=42\n", "%", toml_default);
    assert(toml_custom  == "paprika=1\neverything_else=42\n",          "%", toml_custom );

    // // For deserialization it works the same way, but in opposite direction.
    // // The custom procedure receives a Toml Value and writes into the slot.
    // custom_value_to_enum :: (toml: Toml_Enum.Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
    //     if info.type != .ENUM return false;
    //     Toml_Enum.expect(toml.type, .INT, parent_name, name);
    //     enum_info :*Type_Info_Enum = xx info;

    //     found := array_find(enum_info.values, toml.int_value);
    //     if !found { log_error("Value % is not a variant of enum %", toml.int_value, enum_info.name); return; }
    //     Reflection.set_enum_value(slot, enum_info, toml.int_value);
    //     return true, true;
    // }

    // // The user can again opt in to using the custom handler at the call site, by setting it in the context.
    // ok3, basket3 := Toml_Enum.deserialize("paprika=\"RED\"\neverything_else=3\n", Basket);                                              assert(ok3);
    // ok4, basket4 := Toml_Enum.deserialize("paprika=2\neverything_else=3\n", Basket,, toml_custom_value_to_type = custom_value_to_enum); assert(ok4);
    // assert(basket3.paprika == .RED && basket3.everything_else == 3, "%", basket3);
    // assert(basket4.paprika == .RED && basket4.everything_else == 3, "%", basket3);
}

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
custom_modified_to_value :: (data: $T, $info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    #if #run info != type_info(ThreeNamed) return false; // Use default serialization for everything else by returning done=false.
    else {
        modified_info :: #run two_renamed_type_info();
        ok, value := Toml_Mod.type_to_value_shared_memory(data, #run (*modified_info).(*Type_Info));
        return true, ok, value;
    }
}
// custom_value_to_modified :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
//     if info != type_info(ThreeNamed) return false;
//     modified_info := two_renamed_type_info();
//     ok := Toml_Mod.value_to_type(toml, slot, *modified_info, parent_name, name);
//     return true, ok;
// }
Toml_Mod :: #import, file "../module.jai"(CUSTOM_TYPE_TO_VALUE = #code custom_modified_to_value(data, info));
#poke_name Toml_Mod custom_modified_to_value;

member_modifications :: () {
    // The custom handlers for modifications to members like omitting, renaming, reordering work in a similar way.
    // In general the trick is to create a new Type_Info with the desired modifications and then use the default serialization/deserialization.
    // Note that often the simplest way to create a new Type_Info is by defining a new Type. When doing so
    // be careful that the member offset_in_bytes is correct with respect to the original Type_Info.
    // In this example we instead make a copy of the original Type_Info and modify it.
    // We still need to be careful not to modify the original Type_info as the it needs to be a shallow copy (for custom handlers with pointers to sub-type_infos).


    // When serializing with the custom handler, the members are renamed and the middle member is omitted.
    three_named := ThreeNamed.{a=1, b=2, c=3};
    ok2, toml2 := Toml_Mod.serialize(three_named); assert(ok2);
    assert(toml2 == "alpha=1\ngamma=3\n", "%", toml2);

    // // Similarly, when deserializing with the custom handler, the members are renamed and the middle member is omitted.
    // // Note that we do not fail on the missing member as it is default initialized (in this case to 0).
    // ok3, three_named3 := Toml.deserialize("a=4\nb=5\nc=6\n", ThreeNamed);                                                           assert(ok3);
    // ok4, three_named4 := Toml.deserialize("alpha=4\ngamma=6\n", ThreeNamed,, toml_custom_value_to_type = custom_value_to_modified); assert(ok4);
    // assert(three_named3.a == 4 && three_named3.b == 5 && three_named3.c == 6, "%", three_named3);
    // assert(three_named4.a == 4 && three_named4.b == 0 && three_named4.c == 6, "%", three_named4);
}

arbitrary_binary_encoding :: () {
    // The custom handlers enable us to do conversions of arbitrary complexity during serialization/deserialization.
    // In this example we show how data in a binary encoding can be serialized to Toml and back.
    // Remember that this binary blob could be at any part of a struct hierarchy,
    // still we do not need to decode the blob before serialization. As we convert it when we encounter it.

    // Serialize a binary encoding with custom type_to_value
    // Depending on the first byte we serialize the data differently.
    magic := Magic_Bytes.{.[0x00, 0x43, 0xf2]}; // Assumes little_endian
    ok, toml  := Toml_Magic.serialize(magic); assert(ok);
    assert(toml == "flag=\"A\"\nsigned=-3517\n", "%", toml);

    magic.bytes[0] = 0x01;
    ok, toml = Toml_Magic.serialize(magic); assert(ok);
    assert(toml == "unaltered=[1, 67, 242]\n", "%", toml);

    // In a custom handler we can also check for invalid data and return done=true, ok=false which will propagate up.
    magic.bytes[0] = 0x02;
    ok = Toml_Magic.serialize(magic); assert(!ok);

//     // Deserialize to the binary encoding with custom value_to_type
//     new_context.toml_custom_value_to_type = custom_value_to_magic;

//     push_context new_context {
//         // When deserializing the data is converted back to the binary encoding from different looking Toml data.
//         ok, magic := Toml.deserialize("flag=\"A\"\nsigned=-3517\n", Magic_Bytes); assert(ok);
//         assert(magic.bytes[0] == 0x00 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

//         ok, magic = Toml.deserialize("unaltered=[1, 67, 242]\n", Magic_Bytes); assert(ok);
//         assert(magic.bytes[0] == 0x01 && magic.bytes[1] == 0x43 && magic.bytes[2] == 0xf2, "%", magic);

//         // Error propagation works the same way as with custom type_to_value.
//         ok = Toml.deserialize("unaltered=[2, 67, 242, 0]\n", Magic_Bytes); assert(!ok);
//     }
}

Magic_Bytes :: struct {
    bytes : [3]u8;
};
custom_magic_to_value :: (data: $T, $info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    #if #run info != type_info(Magic_Bytes) return false;
    else {
        ret: Value; // Defaults inits to Table
        if data.bytes[0] == {
        case 0;
            ok, flag    := Toml_Magic.type_to_value_shared_memory("A", type_info(string)); if !ok return;
            ok=, signed := Toml_Magic.type_to_value_shared_memory((*data.bytes[1]).(*s16).*, type_info(s16)); if !ok return;
            array_add(*ret.table, .{key="flag", value=flag}, .{key="signed", value=signed});
        case 1;
            ok, array := Toml_Magic.type_to_value_shared_memory(data.bytes, type_info([3]u8)); if !ok return;
            array_add(*ret.table, .{key="unaltered", value=array});
        case;
            log_error("Invalid Magic_Bytes: %", data);
            return;
        }
        return true, true, ret;
    }
}
Toml_Magic :: #import, file "../module.jai"(CUSTOM_TYPE_TO_VALUE = #code custom_magic_to_value(data, info));
#poke_name Toml_Magic custom_magic_to_value;
// custom_value_to_magic :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
//     if info != type_info(Magic_Bytes) return false;

//     if toml.type != .TABLE { log_error("Expected table for Magic_Bytes, got %", toml.type); return; }
//     if toml.table.count == {
//     case 2;
//         if toml.table[0].key != "flag"   { log_error("Expected key 'flag' for Magic_Bytes, got %",   toml.table[0].key); return; }
//         if toml.table[1].key != "signed" { log_error("Expected key 'signed' for Magic_Bytes, got %", toml.table[1].key); return; }


//         Flag :: enum u8 { A :: 0; }
//         ok := Toml.value_to_type(toml.table[0].value, slot, type_info(Flag), name, "flag"); if !ok return;
//         ok = Toml.value_to_type(toml.table[1].value, slot+1, type_info(s16), name, "signed");
//         return true, ok;
//     case 1;
//         if toml.table[0].key != "unaltered" { log_error("Expected key 'unaltered' for Magic_Bytes, got %", toml.table[0].key); return; }
//         ok := Toml.value_to_type(toml.table[0].value, slot, type_info([3]u8), name, "unaltered"); if !ok return;
//         if slot.(*Magic_Bytes).bytes[0] != 0x01 {
//             log_error("Expected 0x01 for unaltered Magic_Bytes, got %", slot.(*Magic_Bytes).bytes[0]);
//             return;
//         }
//         log("Magic_Bytes unaltered: %", slot.(*Magic_Bytes).bytes);
//         return true, ok;
//     }
//     log_error("Expected 1 or 2 keys for Magic_Bytes, got %", toml.table.count);
//     return;
// }

// error_on_superfluous_keys :: () {
//     // By default the Toml module ignores superfluous keys in a table.
//     // We can use a custom handler to error on superfluous keys.
//     catch_superfluous_keys :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
//         if info.type != .STRUCT || toml.type != .TABLE return false;
//         struct_info :*Type_Info_Struct = xx info;
//         if array_find(struct_info.notes, "SumType") return false; // SumTypes never allow superfluous fields

//         for keyvalue: toml.table {
//             for member: struct_info.members {
//                 if member.flags & (.CONSTANT |.IMPORTED) continue;
//                 if keyvalue.key == member.name continue keyvalue;
//             }
//             log_error("Superfluous key `%` in %.%", keyvalue.key, parent_name, name);
//             return true, false; // We are done, we found an error
//         }
//         return false; // We are not done since we are only validating here, the Value still needs to be deserialized
//     }

//     OnlyA :: struct {
//         a: u8;
//     }
//     // Normally superfluous keys are ignored.
//     ok := Toml.deserialize("a=1 \n b=2", OnlyA); assert(ok);
//     // With the custom handler we can error on them.
//     ok  = Toml.deserialize("a=1 \n b=2", OnlyA,, toml_custom_value_to_type = catch_superfluous_keys); assert(!ok);
// }

polymorphic_types_like_hashtable_support :: () {
    #import "Hash_Table";

    Str_To_U8 :: Table(string, u8);
    my_hash_table: Str_To_U8;

    // Serialize the Hash_Table with the custom handler.
    table_add(*my_hash_table, "one", 1);
    table_add(*my_hash_table, "two", 2);
    ok, toml := Toml_Polymorph.serialize(my_hash_table); assert(ok);
    assert(toml == "one=1\ntwo=2\n" || toml == "two=2\none=1\n", "%", toml);

    // The custom handle has a generic implementation so works with any specialization of a Hash_Table.
    // The key does not need to be a string, but it will be serialized as a string.
    float_table: Table(float, *u8);
    table_add(*float_table, 3.3, New(u8)).*.* = 3;
    ok=, float_toml := Toml_Polymorph.serialize(float_table); assert(ok);
    assert(float_toml == "\"3.3\"=3\n", "%", float_toml);

    // // Deserialization for polymorphic types is likely to be more difficult. In the case of Hash_Table we need to be able to call table_add.
    // // This is a polymorphic procedure thus we need to know the types at compile time to be able to call it.
    // // - We could write a metaprogram that inserts a switch statement holding all possible Hash_Tables used in the application.
    // // - We could provide limited support by reimplementing table_add with a slot/info interface, note however this also requires us to reimplement
    // // other procedures like hash_function and compare_function which may be user defined in which case we can't.
    // // An alternative approach is to reimplement the Toml module to generate all code at compile time instead of the current runtime reflection slot/info interface.
    // // For now we just opt to provide a helper procedure to make it easy for a user to add support for each of their Hash_Tables.
    // custom_value_to_hashtable :: (toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
    //     // We have not found a way to make a generic implementation for any Hash_Table, so instead we need to specialize deserialization for each Hash_Table parameterization we want to support.
    //     done, ok := value_to_hashtable(Str_To_U8, toml, slot, info, name, parent_name);
    //     if done return done, ok;

    //     // Runtime check if we did not forget to add a Hash_Table specialization.
    //     if info.type != .STRUCT return false;
    //     struct_info :*Type_Info_Struct= xx info;
    //     assert(struct_info.polymorph_source_struct != type_info(Table(void, void)).polymorph_source_struct,
    //         "Unsupported Hash_Table specialization: %", struct_info.name);
    //     return false;
    // }

    // // Deserialize the Hash_Table with a custom handler.
    // ok, my_hash_table = Toml_Polymorph.deserialize("three=3\nfour=4\n", Str_To_U8,, toml_custom_value_to_type = custom_value_to_hashtable); assert(ok);
    // assert(my_hash_table.count == 2);
    // three:, ok = table_find(*my_hash_table, "three"); assert(ok);
    // four:, ok = table_find(*my_hash_table, "four"); assert(ok);
    // assert(three == 3 && four == 4, "%", my_hash_table);
}

// // Helper procedure for deserializing a specific type of Hash_Table (Table_Type).
// // This procedure needs to be called in the custom handler for every type of hash table..
// value_to_hashtable :: ($Table_Type: Type, toml: Value, slot: *void, info: *Type_Info, name:string, parent_name:string) -> done:=true, ok:=false {
//     if info != type_info(Table_Type) return false;
//     struct_info :*Type_Info_Struct= xx info;
//     assert(info.type == .STRUCT);
//     assert(struct_info.polymorph_source_struct == type_info(Table(void, void)).polymorph_source_struct);
//     expect(toml.type, .TABLE, parent_name, name);

//     hash_table := slot.(*Table_Type);
//     table_ensure_space(hash_table, toml.table.count);
//     for keyvalue: toml.table {
//         value: Table_Type.Value_Type;
//         ok := Toml_Polymorph.value_to_type(keyvalue.value, *value, type_info(Table_Type.Value_Type), name, keyvalue.key); if !ok return;
//         table_add(hash_table, keyvalue.key, value); // How to call table_add in the generic case when we only have slot and type_info?
//     }
//     return true, true;
// }

// By default the Toml module does not support Hash_Tables.
// We can use custom handlers to serialize and deserialize them.
// To make a generic implementation for all parameterization of Hash_Table we need to do a bit more work
// like getting the type_info of each member and reimplementing the for_expansion.
custom_hashtable_to_value :: (data: $T, $info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    #if #run info.type != .STRUCT then return false;
    struct_info :: info.(*Type_Info_Struct);
    #if #run struct_info.polymorph_source_struct != type_info(Table(void, void)).polymorph_source_struct then return false;
    else {
        table: [..]Toml_Polymorph.KeyValue;
        for data {
            ok, key_as_value := Toml_Polymorph.type_to_value_shared_memory(it_index, type_info(data.Key_Type));   if !ok return;
            ok=, value       := Toml_Polymorph.type_to_value_shared_memory(it, type_info(data.Value_Type)); if !ok return;

            // Serialize the key as a string regardless of what type it is in the Hash_Table.
            builder: String_Builder;
            if key_as_value.type == .STRING Toml_Polymorph.print_to_builder_escaped(*builder, key_as_value.string_value, true);
            else                            Toml_Polymorph.print_inline_value_to_builder(*builder, key_as_value);
            key := builder_to_string(*builder);

            array_add(*table, .{key=key, value=value});
        }
        return true, true, .{type=.TABLE, table=table};
    }
}
Toml_Polymorph :: #import, file "../module.jai"(CUSTOM_TYPE_TO_VALUE = #code custom_hashtable_to_value(data, info));
#poke_name Toml_Polymorph custom_hashtable_to_value;

#import "Basic";
Reflection :: #import "Reflection";
