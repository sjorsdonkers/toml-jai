
main :: () {
    push_allocator(temp);

    args := get_command_line_arguments(); if args.count != 2 exit(1);
    toml_data := read_entire_file(args[1]);

    start := seconds_since_init();
    ok    := Toml.string_to_value_shared_memory(toml_data);
    end   := seconds_since_init();

    if !ok exit(1);
    print("%\n", end-start);
}

using Toml :: #import, file "../../module.jai";
#import "Basic";
#import "File";
