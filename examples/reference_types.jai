
main :: () {
    Inner :: struct {
        str: string;
    }
    Outer :: struct {
        p_s16: *s16;
        p_inner: *Inner;
    }
    // heap := create_heap(context.allocator);
    toml := Toml.deserialize("p_s16 = 36\np_inner = {str = 'Barry'}", Toml.Value); //,, allocator=heap);
    toml2 := Toml.deserialize(toml, Outer);
    // destroy_heap(heap);
    print("toml2: %\n", toml2);
    print("toml2.p_s16: %\n",   <<toml2.p_s16  );
    print("toml2.p_inner: %\n", <<toml2.p_inner);

    Array_View :: struct {
        ocean: []s16;
    }
    toml3 := Toml.deserialize("ocean = [1, 2, 3]", Array_View);
    print("toml3: %\n", toml3);
    assert(toml3.ocean[2] == 3);
}

Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";

#scope_file
