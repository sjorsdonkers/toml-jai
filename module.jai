// STRICT enables additional checks like invalid utf8, control chars or leading 0s, misplaced _s, whitespace, ..
#module_parameters(STRICT := true);

Toml_Context :: struct {
    // The Value used to represent null values in the toml.
    null_value    := Value.{type=.STRING, string_value="~null~"};
    // The note used to indicate optional fields in structs, default: @TomlOptional
    optional_note := "TomlOptional";

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
#load "src/datetime.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
#load "src/parser.jai";
#load "src/lexer.jai";

#scope_module
#import "Basic";
#import "File";
#import "String";
#import "Math";
#import "Unicode";
#import "Flat_Pool";
#import "Text_File_Handler";
Reflection :: #import "Reflection";
