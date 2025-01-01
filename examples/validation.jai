reassignment :: () {
    // Not allowed to reassign a value
    ok:= deserialize("a = 5 \n a = 6", Value);        assert(!ok);
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

keys :: () {
    // Bare keys may only contain A-Za-z0-9_- characters
    ok:= deserialize("a\\ = 5", Value);      assert(!ok);
    ok = deserialize("a£ = 5", Value);       assert(!ok);
    ok = deserialize("+a = 5", Value);       assert(!ok);
    ok = deserialize("a: = 5", Value);       assert(!ok);
    ok = deserialize("a = {🔥 = 5}", Value); assert(!ok);
    ok = deserialize(" = 5", Value); assert(!ok);

    // Multi-line keys are not allowed
    ok = deserialize("a\nb = 5", Value);                  assert(!ok);
    ok = deserialize("\"\"\"a\"\"\" = 5", Value);         assert(!ok);
    ok = deserialize("'''a''' = 5", Value);               assert(!ok);
    ok = deserialize("a = { \"\"\"b\"\"\" = 5 }", Value); assert(!ok);
    ok = deserialize("a = { '''b''' = 5 }", Value);       assert(!ok);

    // Key equivalence is resolved after unescaping and removing quotes
    ok = deserialize("a = 5   \n \"a\" = 6", Value);            assert(!ok);
    ok = deserialize("'a' = 5 \n \"a\" = 6", Value);            assert(!ok);
    ok = deserialize("'🔥' = 5 \n \"\\U0001F525\" = 6", Value); assert(!ok);
}

strings :: () {
    // Literal string key part must be on a single line
    ok:= deserialize("'a\nb' = 5", Value); assert(!ok);
    // Literal key cannot contain single quotes itself
    ok = deserialize("'a'b' = 5", Value);  assert(!ok);
}

end_lines :: () {
    //
    // INVALID TOML, but we allow it
    //

    // Almost anywhere where whitespace is allowed we also allow newlines
    // Between dotted keys
    ok:= deserialize("a\n.\nb = 5", Value); assert(ok);
    // In inline-tables
    ok = deserialize("a = {b \n = \n 5 \n , \n c=3}", Value); assert(ok);
    // Surrounding assignments
    ok = deserialize("a \n = \n 5", Value); assert(ok);
    // Within headers
    ok = deserialize("[[\na\n]] \n [\nb \n .c \n] \n c=6", Value); assert(ok);

    // We allow new lines to be omitted in places where they are required
    // After headers
    ok = deserialize("[[a]][b]c=6[[a]]b={c=6}", Value); assert(ok);
    // After key-value pairs
    ok = deserialize("a=5 b=7", Value); assert(ok);
}

main :: () {
    reassignment();
    keys();
    strings();
    end_lines();
}

#import, file "../module.jai";
#import "Basic";
