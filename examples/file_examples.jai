
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
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    toml := Toml.deserialize(contents, Toml.Value,, allocator=heap);
    print("File: % ", filepath);
    Toml.print_value(toml);
    print("\n");
}

Toml :: #import, file "../module.jai";
#import "Basic";
#import "File";
