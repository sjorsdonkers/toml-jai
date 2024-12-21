// Does not support:
// - Rejecting all control characters
// - Rejecting values that overwrite / append to previous ones
// - Full toml validation like newlines in an inline table or numbers with leading zeros or _s
// - Error propagation

parse :: (contents: string) -> ok:=false, root_table:Value=.{} {
     // TODO array_free on the VIEW is fine as it uses the context allocator
     // Still, the return type of tokenize should change back to a RESIZABLE array when it supports defaults
    ok, tokens := tokenize(contents); defer array_free(tokens);                       if !ok return;
    scope  := Scope.{contents, tokens, 0, ""};

    // At top level we can expect ([[keys]], [keys], keys = value)
    root_table := Value.{type=.TABLE, table=resizable(KeyValue.[])};
    current_table := *root_table;
    while has_next(scope) {
        token := peek_token(scope);
        if token.type == Token.Type.SCOPE_BRACKET {
            ok=, current_table = parse_header(*root_table, eat_scope(*scope, token)); if !ok return;
        } else {
            ok=, key_scope := eat_scope_until(*scope, Token.Type.ASSIGN);             if !ok return;
            ok=, leaf_value := parse_key(current_table, key_scope);                   if !ok return;
            ok=, leaf_value.* = parse_value(leaf_value, *scope);                      if !ok return;
        }
    }
    return true, root_table;
}

#scope_file

parse_header :: (root_table: *Value, scope: Scope) -> ok:=false, value:*Value=null {
    if !has_next(scope) || peek_token(scope).type != Token.Type.SCOPE_BRACKET{
        // Parse [table] header
        ok, current_table, is_new := parse_key(root_table, scope); if !ok return;
        if !is_new && current_table.type != Value.Type.TABLE {
            return_with_error_line(scope.source, peek(scope.tokens).loc, "Cannot use key as Tables as it already has a value: %", current_table.type);
        }
        return true, current_table;
    } else {
        // Parse [[array of tables]] header
        aot_scope := eat_scope(*scope, eat_token(*scope)); // Eat the inner brackets
        if scope.tokens.count > aot_scope.tokens.count + 1 { // No tokens between the closing brackets `]]` allowed
            error_token:= scope.tokens[1 + aot_scope.tokens.count];
            return_with_error_line(scope.source, error_token.loc, "Unexpected % in Array of Tables header", error_token.type);
        }

        ok, current_table, is_new := parse_key(root_table, aot_scope); if !ok return;
        if current_table.type != .ARRAY {
            if !is_new { return_with_error_line(aot_scope.source, peek(aot_scope.tokens).loc, "Cannot use key as Array of Tables as it already has a value: %", current_table.type); }
            current_table.* = .{type=.ARRAY, array=resizable(Value.[])};
        }
        array_add(*current_table.array, Value.{type=.TABLE, table=resizable(KeyValue.[])});
        return true, peek_pointer(current_table.array);
    }
}

// Parse: key. key.'key'."etc"
parse_key :: (parent: *Value, scope: Scope) -> ok:=false, leaf:*Value=null, leaf_is_new:bool=false {
    if !has_next(scope) { return_with_error("Unexpected end of scope while parsing key"); }
    if parent.type != Value.Type.TABLE { return_with_error("Cannot use key as table as it already has a value: %", parent.type); }

    // Get or insert key
    find_or_insert_new :: (array: *[..]KeyValue, key: string) -> is_new:bool, *Value {
        for array.* if it.key == key { return false, *it.value; }
        array_add(array, KeyValue.{key=copy_string(key), value=.{type=.TABLE, table=resizable(KeyValue.[])}});
        return true, *peek_pointer(array.*).value;
    }
    ok, token := eat_expected_key(*scope, .LITERAL); if !ok return;
    current_is_new, current_table := find_or_insert_new(*parent.table, token.str);

    // Check for dotted keys
    if has_next(scope) {
        ok = eat_expected_key(*scope, .DOT); if !ok return;
        // If this is an Array of Tables header then we are going to add into its last table
        if current_table.type == Value.Type.ARRAY then { current_table = peek_pointer(current_table.array); }
        ok=, current_table, current_is_new = parse_key(current_table, scope); if !ok return;
    }
    return true, current_table, current_is_new;
}

// * current_table is null for values in arrays
parse_value :: (current_table: *Value, scope: *Scope) -> ok:=false, value:Value=.{} { // TODO only assign value if key is empty table
    if !has_next(scope) { return_with_error("Unexpected end of file while parsing value"); }

    token := peek_token(scope);
    if token.type == {
    case .SCOPE_BRACE;   ok, value := parse_inline_table(current_table, eat_scope(scope, token)); return ok, value;
    case .SCOPE_BRACKET; ok, value := parse_array(eat_scope(scope, token));                       return ok, value;
    case;                ok, value := parse_literal(scope);                                       return ok, value;
    }
}

parse_inline_table :: (current_table: *Value, scope: Scope) -> ok:=false, table:Value=.{} {
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    table_root := Value.{type=.TABLE, table=resizable(KeyValue.[])}; // Needed for tables in arrays that have no parent
    if current_table == null { current_table = *table_root; }
    while has_next(scope) {
        ok, key_scope := eat_scope_until(*scope, Token.Type.ASSIGN); if !ok return;
        ok=, leaf_value := parse_key(current_table, key_scope);      if !ok return;
        ok=, leaf_value.* = parse_value(leaf_value, *scope);         if !ok return;
        if has_next(scope, 2) { eat_expected(*scope, Token.Type.COMMA); } // Inline tables are not allowed to have trailing commas
    }
    return true, current_table.*;
}

parse_array :: (scope: Scope) -> ok:=false, array:Value=.{} {
    values : [..]Value;
    while has_next(scope) {
        ok, value := parse_value(null, *scope); if !ok return;
        array_add(*values, value);
        if has_next(scope) { eat_expected(*scope, Token.Type.COMMA); }
    }
    return true, .{type=.ARRAY, array=values};
}

parse_literal :: (scope: *Scope) -> ok:=false, literal:Value=.{} {
    token := eat_token(scope);
    if token.type == {
    case .LITERAL;       #through;
    case .LITERAL_MULTI; return true, .{type=.STRING, string_value=copy_string(token.str)};
    case .BASIC;         #through;
    case .BASIC_MULTI;
        ok, unescaped := unescape(token, scope.source); if !ok return;
        return true, .{type=.STRING, string_value=unescaped};
    case .RAW;
        // Parse boolean
        if token.str == "true" { return true, .{type=.BOOL, bool_value=true}; }
        if token.str == "false" { return true, .{type=.BOOL, bool_value=false}; }

        // Parse integer
        clean_str := replace(token.str, "_", ""); // TODO make number specific to check before and after _ is digit / hex etc
        if begins_with(token.str, "0x") {
            advance(*clean_str, 2);
            hex_value, success, remainder := string_to_int_checked(clean_str, 16, s64);
            if success && remainder.count == 0 { return true, .{type=.INT, int_value=hex_value}; }
        } else if begins_with(token.str, "0b") {
            advance(*clean_str, 2);
            bin_value, success, remainder := string_to_int_checked(clean_str, 2, s64);
            if success && remainder.count == 0 { return true, .{type=.INT, int_value=bin_value}; }
        } else if begins_with(token.str, "0o") {
            advance(*clean_str, 2);
            oct_value, success, remainder := string_to_int_checked(clean_str, 8, s64);
            if success && remainder.count == 0 { return true, .{type=.INT, int_value=oct_value}; }
        } else {
            int_value, success, remainder := string_to_int_checked(clean_str, 10, s64);
            // TODO detect leading zeros error, note 00 can be the start of a time
            if success && remainder.count == 0 { return true, .{type=.INT, int_value=int_value}; }
        }

        // Parse float
        float_value, success, remainder := string_to_float64(clean_str);
        // TODO detect illegal floats: .7  7.  3.e+20 ... leading zeros
        if success && remainder.count == 0 { return true, .{type=.FLOAT, float_value=float_value}; }
        if token.str == "inf" || token.str == "+inf" { return true, .{type=.FLOAT, float_value=FLOAT64_INFINITY}; }
        if token.str == "-inf"                       { return true, .{type=.FLOAT, float_value=-FLOAT64_INFINITY}; }
        if token.str == "nan" || token.str == "+nan" { return true, .{type=.FLOAT, float_value=FLOAT64_NAN}; }
        if token.str == "-nan"                       { return true, .{type=.FLOAT, float_value=-FLOAT64_NAN}; }

        // If date, check if next token is time separated by single space: 1979-05-27 07:32:00Z
        date_input := token.str;
        if has_next(scope) {
            next := peek_token(scope);
            if next.type == .RAW
            && (token.str.data + token.str.count).* == #char " "
            && token.str.data + token.str.count + 1 == next.str.data {
                date_input.count += 1 + eat_token(scope).str.count;
            }
        }
        success=, chrono := parse_datetime(date_input);
        if success { return true, .{type=.DATETIME, datetime=chrono}; }

        return_with_error_line(scope.source, token.loc, "Unable to parse literal %", token.str);
    case; return_with_error_line(scope.source, token.loc, "Unexpected token %, expected a value", token.type);
    }
}

unescape :: (basic_token: Token, source: string) -> ok:=false, escaped:string="" {
    assert(basic_token.type == Token.Type.BASIC || basic_token.type == Token.Type.BASIC_MULTI);
    basic := basic_token.str;

    builder: String_Builder;
    pos := 0;
    while pos < basic.count {
        if basic[pos] != #char "\\" {
            append(*builder, basic[pos]);
            pos += 1;
            continue;
        }
        if pos + 1 >= basic.count {return_with_error_line(source, basic_token.loc, "Unterminated escape sequence"); }

        if basic[pos + 1] == {
        case #char "b";  append(*builder, #char "\x08"); pos += 2;
        case #char "t";  append(*builder, #char "\t");   pos += 2;
        case #char "n";  append(*builder, #char "\n");   pos += 2;
        case #char "f";  append(*builder, #char "\x0c"); pos += 2;
        case #char "r";  append(*builder, #char "\r");   pos += 2;
        case #char "\""; append(*builder, #char "\"");   pos += 2;
        case #char "\\"; append(*builder, #char "\\");   pos += 2;
        case #char "\r"; #through;
        case #char "\n";
            pos += 2;
            while (pos < basic.count) && ( basic[pos] == #char " " || basic[pos] == #char "\t" || basic[pos] == #char "\r" || basic[pos] == #char "\n") {
                pos += 1;
            }
        case #char "u"; #through;
        case #char "U";
            num_digits: s32 = xx ifx basic[pos + 1] == #char "u" then 4 else 8;
            pos += 2;

            if pos + num_digits > basic.count {return_with_error_line(source, basic_token.loc, "Expected % characters in the unicode escape sequence", num_digits); }
            unicode_hex_str := slice(basic, pos, num_digits);
            hex_value, success, remainder := string_to_int_checked(unicode_hex_str, 16, u32);
            if !success || remainder.count != 0 { return_with_error_line(source, basic_token.loc, "not valid unicode"); } // TODO improve loc, including \n

            buf: [4]u8;
            tmp := string.{4, buf.data};
            character_utf32_to_utf8(hex_value, *tmp);

            append(*builder, tmp);
            pos += num_digits;
        case; return_with_error_line(source, basic_token.loc, "Invalid escape sequence."); // TODO improve loc, including \n
        }
    }
    return true, builder_to_string(*builder);
}

Scope :: struct {
    source: string;
    tokens: []Token;
    pos: s64 = 0;
    remaining_key: string;
}
has_next :: (scope: Scope, count:=1) -> bool {
    return scope.pos + count -1 < scope.tokens.count;
}
peek_token :: (scope: Scope) -> Token {
    return scope.tokens[scope.pos];
}
eat_token :: (scope: *Scope) -> Token {
    token := peek_token(scope);
    scope.pos += 1;
    return token;
}
eat_expected :: (scope: *Scope, expected: Token.Type) -> ok:=false {
    token := eat_token(scope);
    if token.type != expected { return_with_error_line(scope.source, token.loc, "Expected %, got %", expected, token.type); }
    return true;
}
// * Return: Only DOT or LITERAL tokens
eat_key :: (scope: *Scope) -> ok:=false, key:Token=.{} {
    original := peek_token(scope);
    if scope.remaining_key.count == 0 {
        if original.type == {
        case .RAW;    scope.remaining_key = original.str; // A raw token may contain several dot separated keys
        case .LITERAL; return true, eat_token(scope);           // A quoted token cannot have sub-keys
        case .BASIC;                                      // Normalize to LITERAL as the unescaped needs to be compared
            toki := eat_token(scope);
            ok:, toki.str = unescape(toki, scope.source); if !ok return;
            toki.type = Token.Type.LITERAL;
            return true, toki;
        case .BASIC_MULTI;   #through;
        case .LITERAL_MULTI; return_with_error_line(scope.source, original.loc, "Cannot use multi-line strings as key");
        case .DOT;           assert(false, "Parser expects lexer to give `.` as RAW, not as DOT");
        case;                return_with_error_line(scope.source, original.loc, "Expected key, got %", original.type);
        }
    }
    // Handling potentially dot separated RAW key
    char_num := cast(s32) inline find_index_from_right(original.str, scope.remaining_key);
    next:, scope.remaining_key = split_from_left_incl(scope.remaining_key, #char ".");
    if scope.remaining_key.count == 0 { eat_token(scope); }
    if next == "." { return true, Token.{type=Token.Type.DOT, loc=Location.{original.loc.line, char_num}}; }
    else           {
        if !is_bare_key(next) { return_with_error_line(scope.source, .{original.loc.line, char_num}, "Invalid key % Bare keys may contain only A-Za-z0-9_- otherwise use quotes", next); }
        return true, Token.{type=Token.Type.LITERAL, str=next, loc=Location.{original.loc.line, char_num}};
    }
}
eat_expected_key :: (scope: *Scope, expected: Token.Type) -> ok:=false, key:Token=.{} {
    ok, token := eat_key(scope); if !ok return;
    if token.type != expected { return_with_error_line(scope.source, token.loc, "Expected %, got %", expected, token.type); }
    return true, token;
}
eat_scope :: (scope: *Scope, edible: Token) -> Scope {
    assert(edible.type == .SCOPE_BRACE || edible.type == .SCOPE_BRACKET);
    scope.pos += edible.scope.count + 1;
    return Scope.{scope.source, edible.scope, 0, ""};
}
// * sub_scope does not contain the scope_end token
eat_scope_until :: (scope: *Scope, scope_end: Token.Type) -> ok:=false, sub_scope:Scope=.{} {
    start_pos := scope.pos;
    while has_next(scope) { // TODO impl for for Scope
        if eat_token(scope).type == scope_end {
            return true, Scope.{scope.source, array_view(scope.tokens, start_pos, scope.pos - start_pos - 1), 0, ""};
        }
    }
    return_with_error_line(scope.source, scope.tokens[start_pos].loc, "Unexpected end of scope. Expected %", scope_end);
}

// .   -> `.`  ``   //     -> ``   ``    // a.b -> `a`  `.b`
// ab  -> `ab` ``   // .ab -> `.`  `ab`  // ab. -> `ab` `.`
split_from_left_incl :: (s: string, separator: u8) -> (left: string, right: string) {
    index := inline find_index_from_left(s, separator);
    if index == -1  return s, "";
    if index == 0  index = 1; // Starts with separator
    return slice(s, 0, index), slice(s, index, s.count - index);
}

// Taken from Basic, modified to check overflow
string_to_int_checked :: (s: string, base := 10, $T := int) -> result: T, success: bool, remainder: string {
    assert(base == 16 || base <= 10);
    if !s return 0, false, "";

    sign : T = 1;
    #if #run type_info(T).signed {
        if s[0] == #char "-" {
            sign = -1;
            advance(*s, 1);
        } else if s[0] == #char "+" {
            advance(*s, 1);
        }
    }

    sum: T = 0;
    cursor := 0;

    if base == 16 {
        while cursor < s.count {
            c := s[cursor];

            value: u8 = ---;
            if is_digit(c)                               { value = c - #char "0"; }
            else if (c >= #char "a") && (c <= #char "f") { value = c - #char "a" + 10; }
            else if (c >= #char "A") && (c <= #char "F") { value = c - #char "A" + 10; }
            else { break; }

            sum *= cast(T) base;
            sum += sign * cast(T)value;
            log("sum: %, sign: %, value: %, c: %", sum, sign, value, c);
            if (sum < 0) ^ (sign < 0) { return 0, false, s; }

            cursor += 1;
        }
    } else {
        while cursor < s.count {
            c := s[cursor];
            if !is_digit(c) break;

            digit := c - #char "0";
            if digit >= base break;

            sum *= cast(T) base;
            sum += sign*cast(T)digit;
            if (sum < 0) ^ (sign < 0) { return 0, false, s; }

            cursor += 1;
        }
    }

    success := (cursor != 0);
    advance(*s, cursor);

    return sum, success, s;
}

#scope_module
is_bare_key :: (str: string) -> bool {
    for str  if !is_alnum(it) && it != #char "-" return false;
    return str.count > 0;
}

#scope_file
#load "lexer.jai";
#import "Basic";
#import "File";
#import "String";
#import "Math";
#import "Unicode";
