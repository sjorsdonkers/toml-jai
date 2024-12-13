main :: () {
    // This Toml module is compatible with the sum-types defined by the Sum_Type module at https://github.com/sjorsdonkers/sum_type-jai
    Expect :: struct {
        nom: string;
        expected: Option(s64);
    }
    none_str := Toml.deserialize("nom = 'Tim'", Expect);
    print("none: %\n", none_str);
    explicit_none := Toml.deserialize("nom = 'Tim'\nexpected.none={}", Expect);
    print("none: %\n", explicit_none);
    some := Toml.deserialize("nom = 'Tim'\nexpected.some = 23", Expect);
    print("some: %\n", some.expected.some);
    print("expected: %\n", unwrap(some.expected));

    MyFood :: Sum_Type (
        .{"Bread", #run MyBread},
        .{"Fruit", #run MyFruit},
    );
    food     := Toml.deserialize("bread = {baguette = 3}", MyFood); print("food: %\n", food);
    bread    := unwrap(food, MyFood.Bread);                         print("bread: %\n", bread);
    baguette := unwrap(bread, MyBread.Baguette);                    print("baguette: %\n", baguette);
    assert(3 == baguette);
    other_food  := Toml.deserialize("[fruit.mango]", MyFood);
    other_fruit := unwrap(other_food, MyFood.Fruit);   print("other_fruit: %\n", other_fruit);
    other_mango := unwrap(other_fruit, MyFruit.Mango); print("other_mango: %\n", other_mango);
    assert(tprint("%", none(string)) == tprint("%", other_mango));

    // Sum_Type makes sure that the first variant is default initialized
    pine0 := Toml.deserialize("[fruit]", MyFood);
    assert(0 == unwrap(unwrap(pine0, MyFood.Fruit), MyFruit.Pineapple));

    kiwi_food  := Toml.deserialize("fruit.kiwi = {spaghetti = 3, macaroni = true, why = 9, anonymous = 88, try = 'B'}", MyFood); print("kiwi_food: %\n", kiwi_food);
    kiwi_fruit := kiwi_food.fruit; print("kiwi_fruit: %\n", kiwi_fruit);
    kiwi       := kiwi_fruit.kiwi; print("kiwi: %\n", kiwi);
    assert("{3, true, {9, 88}, B}" == tprint("%", kiwi)); // Using sub-members need to have their offset_in_bytes combined with the using member's offset_in_bytes

    // Test toml of array of optionals
    Expect2 :: struct {
        nom: string;
        expected: [..]Option(s64);
    }
    array := Toml.deserialize("nom = 'Tim'\nexpected = [{some=23}, {some=46}]", Expect2);
    for array.expected { print("% ", it.some); assert(unwrap(it) == (1+it_index)*23); }
    print("array!\n");

    none_array := Toml.deserialize("nom = 'Tim'\n[[expected]]\n[[expected]]\nsome=3\n[[expected]]\n", Expect2);
    print("% none some none array!\n", none_array);

    Expect3 :: struct {
        nom: string;
        expected: [..]MyFruit;
    }
    fruit_bowl := Toml.deserialize("nom = 'Tim'\nexpected = [{Pineapple=7}, {Mango.Some='arrr'}]\n", Expect3);
    print("fruit_bowl: %\n", fruit_bowl);
}
MyStruct :: struct {
    spaghetti: s32;
    macaroni: bool;
    struct {
        why: s64;
        anonymous: s16;
    }
    using try : enum { // The name `try` is optional (so `using enum {`), but without a name a weird inaccessible value is created
        A;
        B;
    }
}
#poke_name ST MyStruct; // To avoid this I think(?) we need $call := #caller_code and #insert,scope(call) to work on structs (Sum_Type)
MyBread :: struct {
    using #as base: Sum_Type( // using #as since `#type,isa` does not expose .Baguette on the variant type MyBread. (using #as also enables the struct to be polymorphic)
        .{"Baguette", u8},
        .{"Croissant", string},
        .{"Pan_De_Sal", #run Option(MyStruct)}, // #run is needed to make sure the specifc Sum_Type is generated before this one
    );
}
#poke_name ST MyBread;
MyFruit :: struct {
    using #as base: Sum_Type (
        .{"Pineapple", u8},
        .{"Mango", #run Option(string)},
        .{"Kiwi", MyStruct},
    );
}
#poke_name ST MyFruit;

Toml :: #import, file "../module.jai";
using ST :: #import, file "../../sum_type-jai/module.jai";
#import "Basic";
#import "File";
