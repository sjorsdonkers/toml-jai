#add_context toml: Toml_Context;
Toml_Context :: struct {
    // The Value used to represent null values in the toml.
    null_value    := Value.{kind=.STRING, string_value="~null~"};

    // The default formatting for int and float values, per-member formatting can override these.
    default_format_int:   FormatInt;
    default_format_float: FormatFloat;

    // Procedures to introduce custom (de)serialization logic for specific types.
    // The procedures set here by default handle: Value and DateTimes.
    custom_type_to_value := default_type_to_value;
    custom_value_to_type := default_value_to_type;
    type_info_cache: Table(*Type_Info_Struct, *Type_Info_Struct); // INTERNAL, tho you can prefill it, which may change

    // Index maps for fast table lookups when table has more keys than the threshold
    index_threshold := 16;                // Minimum number of keys in a table to start using a hashmap for lookups
    index_maps: [..] Table(string, s64) ; // INTERNAL Array of hashmaps, each maps key string to index in table.table array
};

#load "src/data.jai";
#load "src/datetime.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
#load "src/parser.jai";
#load "src/lexer.jai";
#load "src/modify_type_info.jai";

#scope_module // Scope is needed to avoid exposing named imports
#import "Basic";
#import "Hash_Table";
#import "String";
Math              :: #import "Math";
Reflection        :: #import "Reflection";
Text_File_Handler :: #import "Text_File_Handler";
Unicode           :: #import "Unicode";
