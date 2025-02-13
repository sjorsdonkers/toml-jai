// The Value that will be used to represent null values for in the toml.
#add_context toml_null_value := Value.{type=.STRING, string_value="~null~"};

// The procedure to introduce custom serialization logic for specific types.
// The procedure that is set here by default handles: Value, Chrono, and SumType.
#add_context toml_custom_type_to_value := default_custom_type_to_value;

// The procedure to introduce custom deserialization logic for specific types.
// The procedure that is set here by default handles: Value, Chrono, and SumType.
#add_context toml_custom_value_to_type := default_custom_value_to_type;

#load "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
