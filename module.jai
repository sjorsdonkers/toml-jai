Toml_Context :: struct {
    // The Value that will be used to represent null values for in the toml.
    null_value := Value.{type=.STRING, string_value="~null~"};

    // Procedures to introduce custom (de)serialization logic for specific types.
    // The procedures set here by default handle: Value, Chrono, and SumType.
    custom_type_to_value := default_custom_type_to_value;
    custom_value_to_type := default_custom_value_to_type;

    // The default formatting for int and float values, per-member formatting can override these.
    default_format_int:   FormatInt;
    default_format_float: FormatFloat;
};

#add_context toml: Toml_Context;

#load "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
