
main :: () {
    read_parse_print("strings.toml");
}

read_parse_print :: (filepath: string) {
    contents := read_entire_file(filepath);
    heap := create_heap(context.allocator);
    defer destroy_heap(heap);
    toml := Toml.deserialize(contents, Toml.Value,, allocator=heap);
    Toml.print_value(toml);
}

Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";
