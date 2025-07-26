main :: () {
    // For control over formatting there are 2 types, global configuration and per-member configuration.
    // The global configuration is set in the context and applies to all members.
    // - toml.default_format_int
    // - toml.default_format_float
    // FormatTable/Array are not implemented.
    // For per-member configuration Format structs are used like FormatFloat and FormatInt.
    // Format structs are intrusive which is counter to the usual aim of this module, however we have not found a feasible alternative.
    floats();
    ints();
}

floats :: () {
    F64 :: struct {
        value: float64;
    };
    FormatF64 :: struct {
        value: FormatFloat;
    };
    val : float64 = 0.0009980;

    // Standard float serialization
    ok, f1 := Toml.serialize(F64.{value=val}); assert(ok);
    assert(f1 == "value=0.000998\n", "Got '%'", f1);

    // The context's print_style can be set to change the format for all floats
    ok, f1  = Toml.serialize(F64.{value=val},, toml=.{default_format_float=.{mode=.SCIENTIFIC, trailing_width=0}}); assert(ok);
    assert(f1 == "value=1e-03\n", "Got '%'", f1);

    // For individual members the FormatFloat type can be used to override the default
    format := FormatF64.{value = .{value=val, mode=.SCIENTIFIC}};
    ok, f1  = Toml.serialize(format); assert(ok);
    assert(f1 == "value=9.98e-04\n", "Got '%'", f1);

    // It is not required to be a float64
    format.value.value = (123456.7).(float32);
    ok, f1  = Toml.serialize(format); assert(ok);
    assert(f1 == "value=1.234567e+05\n", "Got '%'", f1);

    // A variant of a float is also supported
    FVariant :: #type,distinct float64;
    F2Variant :: #type,isa FVariant;
    format.value.value = (430467.21).(F2Variant);
    ok, f1  = Toml.serialize(format); assert(ok);
    assert(f1 == "value=4.304672e+05\n", "Got '%'", f1);
}

ints ::() {
    S64 :: struct {
        value: s64;
    };
    FormatS64 :: struct {
        value: FormatInt;
    };
    val : s64 = 42;

    // Standard int serialization
    ok, i1 := Toml.serialize(S64.{value=val}); assert(ok);
    assert(i1 == "value=42\n", "Got '%'", i1);

    // The context's print_style can be set to change the format for all ints
    ok, i1  = Toml.serialize(S64.{value=val},, toml=.{default_format_int=.{base=16}}); assert(ok);
    assert(i1 == "value=2a\n", "Got '%'", i1);

    // For individual members the FormatInt type can be used to override the default
    format := FormatS64.{value = .{value=val, base=2}};
    ok, i1  = Toml.serialize(format); assert(ok);
    assert(i1 == "value=101010\n", "Got '%'", i1);

    // It is not required to be a int64
    format.value.value = (123456).(s32);
    ok, i1  = Toml.serialize(format); assert(ok);
    assert(i1 == "value=11110001001000000\n", "Got '%'", i1);

    // A variant of a int is also supported
    IVariant :: #type,distinct s64;
    I2Variant :: #type,isa IVariant;
    format.value.value = (43046721).(I2Variant);
    ok, i1  = Toml.serialize(format); assert(ok);
    assert(i1 == "value=10100100001101011101000001\n", "Got '%'", i1);
}

using Toml :: #import, file "../module.jai";
#import "Basic";
