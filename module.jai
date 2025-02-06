// CUSTOM_HANDLERS = true adds two procedure pointers to #Context: toml_custom_type_to_value and toml_custom_value_to_type.
// These can be set by the user for validation or to change how certain types are converted.
//
// NULL_STRING is the string that will be used to represent null values in the output.

#module_parameters(CUSTOM_HANDLERS := false, NULL_STRING := "~null~");
NULL_VALUE :: Value.{type=.STRING, string_value=NULL_STRING};

#load "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
