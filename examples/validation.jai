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
    ok = deserialize("[a]\n b=3 \n [a] c=4", Value); assert(!ok); // STRICT
    // According to TOML spec reopening an inline array is not allowed
    ok = deserialize("a=[3,4] \n [[a]] b=4", Value); assert(!ok); // STRICT
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
    // Explicit \r is not removed from keys. \r\n is different from \n
    ok = deserialize("\"a \\n b\" = 5 \n \"a \\r\\n b\" = 6", Value); assert(ok);

}

strings :: () {
    // Literal string must be on a single line
    ok:= deserialize("'a\nb' = 5", Value); assert(!ok);
    // Literal string cannot contain single quotes
    ok = deserialize("'a'b' = 5", Value);  assert(!ok);

    // Basic string must be on a single line
    ok = deserialize("\"a\nb\" = 5", Value);  assert(!ok);
    // Basic string cannot contain unescaped double quotes or backslashes
    ok = deserialize("\"a\"b\" = 5", Value);  assert(!ok);
    ok = deserialize("\"a\\ .b\" = 5", Value);  assert(!ok);

    // Multi-line basic strings may not contain unescaped backslashes except at the end of the line
    ok = deserialize("5 = \"\"\"a\\ b\"\"\"", Value);  assert(!ok);

    // Currently \r\n control characters are not normalized to \n TODO
    ok=, rn:= deserialize("a = '''a\r\nb'''", Value); assert(ok);
    ok=,  n:= deserialize("a = '''a\nb'''  ", Value); assert(ok);
    print("%\n%\n",rn.table[0].string_value, n.table[0].string_value);
    assert(rn != n);

    // We check for invalid control / UTF-8 characters

    // Basic strings may not contain unescaped control characters: U+0000 to U+0008, U+000A to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" continue; // We do check this
        if control == "\t" continue;
        ok = deserialize(tprint("\"a%b\" = 5", control), Value);          assert(!ok);
    }
    ok = deserialize("\"a\u007F.b\" = 5", Value);                         assert(!ok);

    // Multi-line basic strings may not contain control characters: U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" || control == "\r" || control == "\t" continue;
        ok = deserialize(tprint("5 = \"\"\"a%b\"\"\"", control), Value);  assert(!ok);
    }
    ok = deserialize("5 = \"\"\"a\u007Fb\"\"\"", Value);                  assert(!ok);

    // Literal strings may not contain unescaped control characters: U+0000 to U+0008, U+000A to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" continue; // We do check this
        if control == "\t" continue;
        ok = deserialize(tprint("'a%b' = 5", control), Value);          assert(!ok);
    }
    ok = deserialize("5 = 'a\u007Fb'", Value);                          assert(!ok);

    // Multi-line literal strings may not contain control characters: U+0000 to U+0008, U+000B, U+000C, U+000E to U+001F, U+007F
    for char: cast(u8, "\u0000")..cast(u8, "\u001F") {
        control:= string.{1, *char};
        if control == "\n" || control == "\r" || control == "\t" continue;
        ok = deserialize(tprint("5 = '''a%b'''", control), Value);  assert(!ok);
    }
    ok = deserialize("5 = '''a\u007Fb'''", Value);                  assert(!ok);
}

end_lines :: () {
    //
    // INVALID TOML, but we allow it
    //

    // Almost anywhere where whitespace is allowed we also allow newlines
    // Between dotted keys
    ok:= deserialize("a\n.\nb = 5", Value); assert(!ok); // STRICT
    // In inline-tables
    ok = deserialize("a = {b \n = \n 5 \n , \n c=3}", Value); assert(!ok); // STRICT
    // Surrounding assignments
    ok = deserialize("a \n = \n 5", Value); assert(!ok); // STRICT
    // Within headers
    ok = deserialize("[[\na\n]] \n [\nb \n .c \n] \n c=6", Value); assert(!ok); // STRICT
}

main :: () {
    reassignment();
    keys();
    strings();
    end_lines();
}

#import, file "../module.jai";
#import "Basic";
