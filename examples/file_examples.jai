
main :: () {
    // These files contain all the example data taken from https://toml.io/en/v1.0.0
    read_parse_print("data/array_of_tables.toml");
    read_parse_print("data/array.toml");
    read_parse_print("data/boolean.toml");
    read_parse_print("data/datetime.toml");
    read_parse_print("data/float.toml");
    read_parse_print("data/inline_table.toml");
    read_parse_print("data/integer.toml");
    read_parse_print("data/keys.toml");
    read_parse_print("data/strings.toml");
    read_parse_print("data/table.toml");
}

read_parse_print :: (filepath: string) {
    contents := read_entire_file(filepath);
    ok, toml := Toml.string_to_type(contents, Toml.Value); assert(ok);
    print("File: %\n", filepath);
    ok=, ser := Toml.type_to_string(toml); assert(ok);
    print("Toml:\n%", ser);
    ok=, toml2 := Toml.string_to_type(ser, Toml.Value); assert(ok);
    ok=, ser2  := Toml.type_to_string(toml2); assert(ok);
    // print("Toml2:\n%", ser2);

    assert(ser == ser2);
}

using Toml :: #import, file "../module.jai";
#import "Basic";
#import "File";
