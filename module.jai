#module_parameters(CUSTOM_HANDLERS := false, NULL_STRING := "~null~");
NULL_VALUE :: Value.{type=.STRING, string_value=NULL_STRING};

#load "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
