


main :: () {
    Expect :: struct {
        nom: string;
        expected: Option(s64);
    }
    none := Toml.deserialize("nom = 'Tim'", Expect);
    print("none: %\n", none);
    explicit_none := Toml.deserialize("nom = 'Tim'\n[expected]", Expect);
    print("none: %\n", explicit_none);
    some := Toml.deserialize("nom = 'Tim'\nexpected = 23", Expect);
    print("some: %\n", some);
    print("expected: %\n", unwrap(some.expected)); // TODO how to print these nicely easily?

    MyFood :: Sum_Type (
        .{"Bread", #run MyBread},
        .{"Fruit", #run MyFruit},
    );
    food     := Toml.deserialize("Bread = {Baguette = 3}", MyFood); print("food: %\n", food);
    bread    := unwrap(food, MyFood.Bread);                         print("bread: %\n", bread);
    baguette := unwrap(bread, MyBread.Baguette);                    print("baguette: %\n", baguette);

    other_food := Toml.deserialize("[Fruit]", MyFood); // Should this be Mango?
}
MyStruct :: struct {
    spaghetti: s32;
    macaroni: bool;
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

Toml :: #import, file "../Toml/module.jai";
ST :: #import, file "../../sum_type-jai/Sum_Type/module.jai";
#import, file "../../sum_type-jai/Sum_Type/module.jai";
#import "Basic";
#import "File";
