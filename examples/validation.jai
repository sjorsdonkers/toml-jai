reassignment :: () {
    // Not allowed to reassign a value
    ok := deserialize("a = 5 \n a = 6", Value);       assert(!ok);
    // Dotted keys implicitly create tables
    ok = deserialize("a.b = 5 \n a = {c=7}", Value);  assert(!ok);
    // Similarly reassignment is also not allowed within inline tables
    ok = deserialize("t = {a = 5, a = 6}", Value);    assert(!ok);
    ok = deserialize("t = {a.b = 5, a = 7}", Value);  assert(!ok);
    // Tables / inline tables are just 2 different ways to define the same data. Cross reassignment is also not allowed
    ok = deserialize("t = {a = 5}\n t.a = 8", Value); assert(!ok);
    // Table headers may not open non-tables
    ok = deserialize("a=5 \n [a]", Value);            assert(!ok);
    // Array of Tables headers may not open non-arrays
    ok = deserialize("a={b=5} \n [[a]]", Value);      assert(!ok);

    //
    // INVALID TOML, but we allow it
    //

    // According to TOML spec reopening a table is not allowed
    ok = deserialize("[a]\n b=3 \n [a] c=4", Value); assert(ok);
    // According to TOML spec reopening an inline array is not allowed
    ok = deserialize("a=[3,4] \n [[a]] b=4", Value); assert(ok);
}

main :: () {
    reassignment();
}

#import, file "../module.jai";
#import "Basic";
