
main :: () {
    Inner :: struct {
        str: u32;
    }
    Outer :: struct {
        p_s16: *s16;
        p_inner: *Inner;
    }
    // heap := create_heap(context.allocator);
    toml := Toml.deserialize("p_s16 = 36\np_inner = {str = 3333}", Toml.Value); //,, allocator=heap);
    toml2 := Toml.deserialize(toml, Outer);
    // destroy_heap(heap);
    print("toml2: %\n", toml2);
    print("toml2.p_s16: %\n",   <<toml2.p_s16  );
    print("toml2.p_inner: %\n", <<toml2.p_inner);

}

Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";

#scope_file
