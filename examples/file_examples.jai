
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
    toml := Toml.deserialize(contents, Toml.Value);
    print("File: %\n", filepath);
    ser   := Toml.serialize(toml);
    print("Toml: %\n", ser);
    toml2 := Toml.deserialize(ser, Toml.Value);
    ser2  := Toml.serialize(toml2);
    assert(ser == ser2);
}

Toml :: #import, file "../module.jai";
#import "Basic";
#import "File";
