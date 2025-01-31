main :: () {
    new_context := context;
    new_context.toml_custom_type_to_value = custom_type_to_value;

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

    new_context.toml_custom_value_to_type = custom_value_to_type;

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
custom_type_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
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
custom_value_to_type :: (toml: Value, slot: *void, info: *Type_Info, parent_name:string, name:string) -> done:=true, ok:=false {
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


using Toml :: #import, file "../module.jai"(CUSTOM_HANDLERS=true);
#import "Basic";
