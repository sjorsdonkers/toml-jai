
main :: () {
    // POINTER
    Inner :: struct {
        str: string;
    }
    Outer :: struct {
        p_s16: *s16;
        p_inner: *Inner;
    }
    pointers_toml := Toml.deserialize("p_s16 = 36\np_inner = {str = 'Barry'}", Outer);
    print("pointers_toml: %\n", pointers_toml);
    print("pointers_toml.p_s16: %\n",   <<pointers_toml.p_s16  );
    print("pointers_toml.p_inner: %\n", <<pointers_toml.p_inner);

    Getal :: #type,distinct u8;

    // Pointer to fixed array with initializer
    Vingt :: struct       {
        number : s8=20;
        getal: Getal= 23;
    }
    Fixed_Array :: struct {
        p_quatre: *[4]Vingt;
    }
    quatre_vingt := Toml.deserialize("p_quatre = [{getal = 9}, {getal = 4}, {number = 3}, {}]", Fixed_Array);
    log("quatre_vingt: %\n", <<quatre_vingt.p_quatre);
    assert((<<quatre_vingt.p_quatre)[0].number == 20);
    assert((<<quatre_vingt.p_quatre)[2].getal == 23);

    // Pointer to variant
    DefaultStruct :: struct {
        a: string="Anton";
        b: s8;
    }
    DefaultVariant :: #type,distinct DefaultStruct;
    MyVar :: struct {
        p_variant: *DefaultVariant;
    }
    mutant := Toml.deserialize("p_variant.b = 3", MyVar);
    print("mutant: %\n", <<mutant.p_variant);
    assert(mutant.p_variant.a == "Anton");

    // ARRAY VIEW
    Array_View :: struct {
        ocean: []s16;
    }
    arrayview_toml := Toml.deserialize("ocean = [1, 2, 3]", Array_View);
    print("arrayview_toml: %\n", arrayview_toml);
    assert(arrayview_toml.ocean[2] == 3);

    // ANY
    Amy :: struct {
        andy: Any;
    }
    toml4 := Toml.deserialize("andy = 3", Amy);
    assert("{3}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = 'hello'", Amy);
    assert("{\"hello\"}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = 3.3", Amy);
    assert("{3.3}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = true", Amy);
    assert("{true}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = [1, 7, 3]", Amy);
    assert("{[1, 7, 3]}" == tprint("%", toml4));
    toml4 = Toml.deserialize("andy = [1, 'd', 3]", Amy);
    print("%\n", toml4);

    AnyAndy :: struct {
        any_andy: s16;
        any_amy: s16;
    }
    OtherAndy :: struct {
        other_andy: string;
        other_amy: string;
    }
    toml5 := Toml.deserialize("[[andy]]\nany_andy = 9\nany_amy = 8\n[[andy]]\nother_andy = 'Peter'\nother_amy = 'Derick'", Amy);
    andies := cast(*[]Toml.Value) toml5.andy.value_pointer;
    any_andy := Toml.deserialize((<<andies)[0], AnyAndy);
    assert("{9, 8}" == tprint("%", any_andy));
    other_andy := Toml.deserialize((<<andies)[1], OtherAndy);
    assert("{\"Peter\", \"Derick\"}" == tprint("%", other_andy));
}

Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";
