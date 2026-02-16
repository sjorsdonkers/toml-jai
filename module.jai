#add_context toml: Toml_Context;
Toml_Context :: struct {
    // The Value used to represent null values in the toml.
    null_value    := Value.{kind=.STRING, string_value="~null~"};
    // The note used to indicate optional fields in structs
    optional_note := "TomlOptional";

    // The default formatting for int and float values, per-member formatting can override these.
    default_format_int:   FormatInt;
    default_format_float: FormatFloat;

    // The following members will likely be moved into a FormatStruct and only apply to structs & variants
    // List of procedures that will be used to modify the Type_Info, to do things like renaming, omitting, reordering, flattening using members.
    // If you need more than 10 use a  procedure that calls several modifiers, maybe that is just how it should work..
    type_info_modifiers: [10] #type (info: *Type_Info_Struct) -> Type_Info_Struct;
    type_info_modifiers[0] = flatten_using_type_info;                 // NOTE: The index may change as more default modifiers are added
    type_info_cache:     Table(*Type_Info_Struct, *Type_Info_Struct); // INTERNAL, tho you can prefill it, which may change

    // Procedures to introduce custom (de)serialization logic for specific types.
    // The procedures set here by default handle: Value and DateTimes.
    custom_type_to_value := default_custom_type_to_value;
    custom_value_to_type := default_custom_value_to_type;

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
