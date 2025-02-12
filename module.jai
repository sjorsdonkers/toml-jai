// NULL_STRING is the string that will be used to represent null values in the output.

#module_parameters(NULL_STRING := "~null~");
NULL_VALUE :: Value.{type=.STRING, string_value=NULL_STRING};

#load "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
