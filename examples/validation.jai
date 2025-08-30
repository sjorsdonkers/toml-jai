main :: () {
    reassignment();
    keys();
    strings();
    end_lines();
    assert(type_info(Value).runtime_size == 48, "%", type_info(Value).runtime_size);
}

reassignment :: () {
    // Not allowed to reassign a value
    ok:= Toml.string_to_type("a = 5 \n a = 6", Value);        assert(!ok);
    // Dotted keys implicitly create tables
    ok = Toml.string_to_type("a.b = 5 \n a = {c=7}", Value);  assert(!ok);
    // Similarly reassignment is also not allowed within inline tables
    ok = Toml.string_to_type("t = {a = 5, a = 6}", Value);    assert(!ok);
    ok = Toml.string_to_type("t = {a.b = 5, a = 7}", Value);  assert(!ok);
    // Tables / inline tables are just 2 different ways to define the same data. Cross reassignment is also not allowed
    ok = Toml.string_to_type("t = {a = 5}\n t.a = 8", Value); assert(!ok);
    // Table headers may not open non-tables
    ok = Toml.string_to_type("a=5 \n [a]", Value);            assert(!ok);
    // Array of Tables headers may not open non-arrays
    ok = Toml.string_to_type("a={b=5} \n [[a]]", Value);      assert(!ok);
    // Reopening a table is not allowed
    ok = Toml.string_to_type("[a]\n b=3 \n [a] c=4", Value); assert(!ok);
    // Reopening an inline array is not allowed
    ok = Toml.string_to_type("a=[3,4] \n [[a]] b=4", Value); assert(!ok);
}

keys :: () {
    // Bare keys may only contain A-Za-z0-9_- characters
    ok:= Toml.string_to_type("a\\ = 5", Value);      assert(!ok);
    ok = Toml.string_to_type("a£ = 5", Value);       assert(!ok);
    ok = Toml.string_to_type("+a = 5", Value);       assert(!ok);
    ok = Toml.string_to_type("a: = 5", Value);       assert(!ok);
    ok = Toml.string_to_type("a = {🔥 = 5}", Value); assert(!ok);
    ok = Toml.string_to_type(" = 5", Value); assert(!ok);

    // Multi-line keys are not allowed
    ok = Toml.string_to_type("a\nb = 5", Value);                  assert(!ok);
    ok = Toml.string_to_type("\"\"\"a\"\"\" = 5", Value);         assert(!ok);
    ok = Toml.string_to_type("'''a''' = 5", Value);               assert(!ok);
    ok = Toml.string_to_type("a = { \"\"\"b\"\"\" = 5 }", Value); assert(!ok);
    ok = Toml.string_to_type("a = { '''b''' = 5 }", Value);       assert(!ok);

    // Key equivalence is resolved after unescaping and removing quotes
    ok = Toml.string_to_type("a = 5   \n \"a\" = 6", Value);            assert(!ok);
    ok = Toml.string_to_type("'a' = 5 \n \"a\" = 6", Value);            assert(!ok);
    ok = Toml.string_to_type("'🔥' = 5 \n \"\\U0001F525\" = 6", Value); assert(!ok);
    // Explicit \r is not removed from keys. \r\n is different from \n
    ok = Toml.string_to_type("\"a \\n b\" = 5 \n \"a \\r\\n b\" = 6", Value); assert(ok);

}

strings :: () {
    // Literal string must be on a single line
    ok:= Toml.string_to_type("'a\nb' = 5", Value); assert(!ok);
    // Literal string cannot contain single quotes
    ok = Toml.string_to_type("'a'b' = 5", Value);  assert(!ok);

    // Basic string must be on a single line
    ok = Toml.string_to_type("\"a\nb\" = 5", Value);   assert(!ok);
    // Basic string cannot contain unescaped double quotes or backslashes
    ok = Toml.string_to_type("\"a\"b\" = 5", Value);   assert(!ok);
    ok = Toml.string_to_type("\"a\\ .b\" = 5", Value); assert(!ok);

    // Multi-line basic strings may not contain unescaped backslashes except at the end of the line
    ok = Toml.string_to_type("5 = \"\"\"a\\ b\"\"\"", Value); assert(!ok);

    // Currently \r\n control characters are not normalized to \n TODO
    ok=, rn:= Toml.string_to_type("a = '''a\r\nb'''", Value); assert(ok);
    ok=,  n:= Toml.string_to_type("a = '''a\nb'''  ", Value); assert(ok);
    print("%\n%\n",rn.table[0].string_value, n.table[0].string_value);
    assert(rn != n);

    // We check for invalid control / UTF-8 characters when STRICT == true

    // Basic strings may not contain unescaped control characters: U+0000 to U+0008, U+000A to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" continue; // We do check this
        if control == "\t" continue;
        ok = Toml.string_to_type(tprint("\"a%b\" = 5", control), Value); assert(!ok);
    }
    ok = Toml.string_to_type("\"a\u007F.b\" = 5", Value);                assert(!ok);

    // Multi-line basic strings may not contain control characters: U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" || control == "\r" || control == "\t" continue;
        ok = Toml.string_to_type(tprint("5 = \"\"\"a%b\"\"\"", control), Value); assert(!ok);
    }
    ok = Toml.string_to_type("5 = \"\"\"a\u007Fb\"\"\"", Value);                 assert(!ok);

    // Literal strings may not contain unescaped control characters: U+0000 to U+0008, U+000A to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" continue; // We do check this
        if control == "\t" continue;
        ok = Toml.string_to_type(tprint("'a%b' = 5", control), Value); assert(!ok);
    }
    ok = Toml.string_to_type("5 = 'a\u007Fb'", Value);                 assert(!ok);

    // Multi-line literal strings may not contain control characters: U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" || control == "\r" || control == "\t" continue;
        ok = Toml.string_to_type(tprint("5 = '''a%b'''", control), Value); assert(!ok);
    }
    ok = Toml.string_to_type("5 = '''a\u007Fb'''", Value);                 assert(!ok);
}

end_lines :: () {
    // Almost anywhere where whitespace is allowed we also allow newlines when STRICT == false
    // Between dotted keys
    ok:= Toml.string_to_type("a\n.\nb = 5", Value); assert(!ok); // STRICT
    // In inline-tables
    ok = Toml.string_to_type("a = {b \n = \n 5 \n , \n c=3}", Value); assert(!ok); // STRICT
    // Surrounding assignments
    ok = Toml.string_to_type("a \n = \n 5", Value); assert(!ok); // STRICT
    // Within headers
    ok = Toml.string_to_type("[[\na\n]] \n [\nb \n .c \n] \n c=6", Value); assert(!ok); // STRICT
}

using Toml :: #import, file "../module.jai";
#import "Basic";
