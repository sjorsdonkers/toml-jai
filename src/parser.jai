// Note this parser is zero-copy except for basic strings as they need to be unescaped
// As such the keys and strings in the returned Value may point into the source string
// Additionally this procedure does not deallocate any temporary memory
// Sets context.toml.index_maps
string_to_value_shared_memory :: (contents: string) -> ok:=false, root_table:Value=.{} {
    ok, tokens := tokenize(contents);  if !ok return; // Not freeing tokens as it will be in a Pool
    scope      := Scope.{contents, tokens, 0, ""};

    // At top level we can expect ([[keys]], [keys], keys = value)
    root_table: Value;
    current_table := *root_table;
    context.toml.index_maps = [..]Table(string, s64).{};
    while has_next(scope) {
        token := peek_token(scope);
        if token.type == .NEWLINE { eat_token(*scope); continue; }

        if token.type == {
        case .SCOPE_BRACKET;        // [table] header
            define(current_table, .HEADER);                                                      // Finalize the previous Table, to prevent re-definition
            header_scope     := eat_scope(*scope, token);
            ok, current_table = parse_key(*root_table, header_scope, true); if !ok return;
            if is_defined(current_table, .DOTTED_KEY) then return_with_error_line(scope.source, peek(scope.tokens).loc, "Cannot redefine Table defined via dotted key");
            if is_defined(current_table, .HEADER)     then return_with_error_line(scope.source, peek(scope.tokens).loc, "Cannot redefine a [Table] / [[Array of Tables]]");
        case .SCOPE_DOUBLE_BRACKET; // [[array of tables]] header
            define(current_table, .HEADER);                                                      // Finalize the previous Table, to prevent re-definition
            header_scope     := eat_scope(*scope, token);
            ok=, aot, is_new := parse_key(*root_table, header_scope, true); if !ok return;
            if is_new then { aot.* = .{kind=.ARRAY, array=[..]Value.{}}; define(aot, .HEADER); } // Create and finalize the Array, to prevent re-definition
            else if (aot.kind != .ARRAY || aot.table.count == 0) then return_with_error_line(header_scope.source, peek(header_scope.tokens).loc, "Cannot use key as Array of Tables as it already has a value: %", aot.kind);
            current_table = array_add(*aot.array);                                               // Add a new entry as current_table
        case;                       // key = value
            ok=, key_scope   := eat_scope_until_assign(*scope);             if !ok return;
            ok=, leaf_value  := parse_key(current_table, key_scope, false); if !ok return;
            ok=, leaf_value.* = parse_value(leaf_value, *scope);            if !ok return;
        }
        if has_next(scope) { eat_expected(*scope, .NEWLINE); if !ok return; }
    }
    return true, root_table;
}

#scope_module

// Parse: key. key.'key'."etc"
parse_key :: (parent: *Value, scope: Scope, parsing_header: bool) -> ok:=false, leaf:*Value=null, leaf_is_new:bool=false {
    if !has_next(scope)      then return_with_error("Unexpected end of scope while parsing key");
    if parent.kind != .TABLE then return_with_error("Cannot use key as table as it already has a value: %", parent.kind);

    ok, token                     := eat_expected_key(*scope, .LITERAL); if !ok return;
    current_is_new, current_value := find_or_insert_key(parent, token.str);
    if is_defined(current_value, .VALUE)                     then return_with_error_line(scope.source, token.loc, "Cannot modify a defined Value: %", token.str);
    if !parsing_header && is_defined(current_value, .HEADER) then return_with_error_line(scope.source, peek(scope.tokens).loc, "Cannot modify a defined Table or Array of Tables");

    // Check for dotted keys
    if has_next(scope) {
        // Dotted keys create and define a table for each key part before the last one, redefining such tables using a [table] header is not allowed.
        if !parsing_header { define(current_value, .DOTTED_KEY); }
        ok = eat_expected_key(*scope, .DOT); if !ok return;
        // If this is an Array of Tables header then we are going to add into its last table
        if current_value.kind == .ARRAY { current_value = peek_pointer(current_value.array); }
        ok=, current_value, current_is_new = parse_key(current_value, scope, parsing_header); if !ok return;
    }

    if !parsing_header && !current_is_new then return_with_error_line(scope.source, peek(scope.tokens).loc, "Key already has a value of kind %", current_value.kind);
    return true, current_value, current_is_new;
}

// * current_table is null for values in arrays
parse_value :: (current_table: *Value, scope: *Scope) -> ok:=false, value:Value=.{} {
    if !has_next(scope) { return_with_error("Unexpected end of file while parsing value"); }

    ok: bool; value: Value;
    token := peek_token(scope);
    if token.type == {
    case .SCOPE_BRACE;   ok, value = parse_inline_table(current_table, eat_scope(scope, token));
    case .SCOPE_BRACKET; ok, value = parse_array(eat_scope(scope, token));
    case;                ok, value = parse_literal(scope);
    }
    define(*value, .VALUE);
    return ok, value;
}

parse_inline_table :: (current_table: *Value, scope: Scope) -> ok:=false, table:Value=.{} {
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    table_root: Value; // Needed for tables in arrays which have no parent
    if current_table == null { current_table = *table_root; }
    while has_next(scope) {
        ok, key_scope    := eat_scope_until_assign(*scope);             if !ok return;
        ok=, leaf_value  := parse_key(current_table, key_scope, false); if !ok return;
        ok=, leaf_value.* = parse_value(leaf_value, *scope);            if !ok return;
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
    return true, .{kind=.ARRAY, array=values};
}

parse_literal :: (scope: *Scope) -> ok:=false, literal:Value=.{} {
    token := eat_token(scope);
    if token.type == {
    case .LITERAL;       #through;
    case .LITERAL_MULTI; return true, .{kind=.STRING, string_value=token.str};
    case .BASIC;         #through;
    case .BASIC_MULTI;
        ok, unescaped := unescape(token, scope.source); if !ok return;
        return true, .{kind=.STRING, string_value=unescaped};
    case .RAW;
        // Parse boolean
        if token.str == "true"  { return true, .{kind=.BOOL, bool_value=true}; }
        if token.str == "false" { return true, .{kind=.BOOL, bool_value=false}; }

        // Parse integer
        us_split := split(token.str, "_");
        clean_str := join(..us_split);

        if clean_str.count >= 2 && clean_str[0] == "0" && (clean_str[1] == "x" || clean_str[1] == "b" || clean_str[1] == "o") {
            if us_split[0].count == 2     then return_with_error_line(scope.source, token.loc, "Invalid _ in base of integer literal %", token.str);
            for us_split if it.count == 0 then return_with_error_line(scope.source, token.loc, "Invalid placement of _ in integer literal %", token.str);

            without_base := slice(clean_str, 2, clean_str.count - 2);
            base := ifx clean_str[1] == "x" then 16 else ifx clean_str[1] == "b" then 2 else 8;
            value, ok, remainder := string_to_int_checked(without_base, base, s64);
            if !ok || remainder.count != 0 then return_with_error_line(scope.source, token.loc, "Invalid hex/binary/octal literal %", token.str);
            return true, .{kind=.INT, int_value=value};
        }
        int_value, ok, remainder := string_to_int_checked(clean_str, 10, s64);
        if ok && remainder.count == 0 {
            for us_split if it.count == 0 then return_with_error_line(scope.source, token.loc, "Invalid placement of _ in integer literal %", token.str);
            start_digit := ifx (clean_str[0] == "+" || clean_str[0] =="-") then 1 else 0;
            if clean_str[start_digit] == "0" && clean_str.count - start_digit > 1 then return_with_error_line(scope.source, token.loc, "Leading zeros are not allowed in integer literal %", token.str);
            return true, .{kind=.INT, int_value=int_value};
        }

        // Parse float
        float_value:, ok, remainder = string_to_float64(clean_str);
        if ok && remainder.count == 0 {
            is_dot_or_e :: inline (c: u8) -> bool { return c == "." || c == "e" || c == "E"; }

            start_digit := ifx (clean_str[0] == "+" || clean_str[0] =="-") then 1 else 0;
            first, second := clean_str[start_digit], clean_str[start_digit + 1]; // We know this is in range otherwise it would be an int
            if is_dot_or_e(first)                   then return_with_error_line(scope.source, token.loc, "Float literals may not start with a dot: %", token.str);
            if first == "0" && !is_dot_or_e(second) then return_with_error_line(scope.source, token.loc, "Leading zeros are not allowed in float literal %", token.str);

            for us_split {
                if it.count == 0                                     then return_with_error_line(scope.source, token.loc, "Invalid placement of _ in float literal %", token.str);
                if is_dot_or_e(it[0]) || is_dot_or_e(it[it.count-1]) then return_with_error_line(scope.source, token.loc, "Invalid placement of ./e in float literal %", token.str);
            }
            for idx: start_digit..clean_str.count-2 {
                if clean_str[idx] == "." && (clean_str[idx + 1] == "e" || clean_str[idx + 1] == "E") then return_with_error_line(scope.source, token.loc, "Invalid .e in float literal %", token.str);
            }
            return true, .{kind=.FLOAT, float_value=float_value};
        }
        if token.str == "inf" || token.str == "+inf" { return true, .{kind=.FLOAT, float_value=Math.FLOAT64_INFINITY}; }
        if token.str == "-inf"                       { return true, .{kind=.FLOAT, float_value=-Math.FLOAT64_INFINITY}; }
        if token.str == "nan" || token.str == "+nan" { return true, .{kind=.FLOAT, float_value=Math.FLOAT64_NAN}; }
        if token.str == "-nan"                       { return true, .{kind=.FLOAT, float_value=-Math.FLOAT64_NAN}; }

        // Parse date, check if next token is time separated by single space: 1979-05-27 07:32:00Z
        date_input := token.str;
        if has_next(scope) {
            next := peek_token(scope);
            if next.type == .RAW
            && (token.str.data + token.str.count).* == " "
            && token.str.data + token.str.count + 1 == next.str.data {
                date_input.count += 1 + eat_token(scope).str.count;
            }
        }
        ok=, chrono := parse_datetime(date_input);
        if ok { return true, .{kind=.DATETIME, datetime=chrono}; }

        return_with_error_line(scope.source, token.loc, "Unable to parse literal %", token.str);
    case; return_with_error_line(scope.source, token.loc, "Unexpected token %, expected a value", token.type);
    }
}

unescape :: (basic_token: Token, source: string) -> ok:=false, unescaped:string="" #no_abc {
    assert(basic_token.type == Token.Type.BASIC || basic_token.type == Token.Type.BASIC_MULTI);
    basic := basic_token.str;

    buffer := alloc_string(basic.count); // Allocate same size as input since unescaped string is always <= input length
    buffer.count = 0;                    // Start with empty buffer, we'll increment it as we write, but need #no_abc
    pos := 0;
    while pos < basic.count {
        if basic[pos] != "\\" {
            buffer[buffer.count] = basic[pos];
            buffer.count += 1;
            pos += 1;
            continue;
        }
        if pos + 1 >= basic.count {return_with_error_line(source, basic_token.loc, "Unterminated escape sequence"); }

        if basic[pos + 1] == {
        case "b";  buffer[buffer.count] = "\x08"; buffer.count += 1; pos += 2;
        case "t";  buffer[buffer.count] = "\t";   buffer.count += 1; pos += 2;
        case "n";  buffer[buffer.count] = "\n";   buffer.count += 1; pos += 2;
        case "f";  buffer[buffer.count] = "\x0c"; buffer.count += 1; pos += 2;
        case "r";  buffer[buffer.count] = "\r";   buffer.count += 1; pos += 2;
        case "\""; buffer[buffer.count] = "\"";   buffer.count += 1; pos += 2;
        case "\\"; buffer[buffer.count] = "\\";   buffer.count += 1; pos += 2;
        case "\r"; #through;
        case "\t"; #through;
        case " ";  #through;
        case "\n";
            if basic_token.type != Token.Type.BASIC_MULTI return_with_error_line(source, basic_token.loc, "Only multi-line basic strings (\"\"\") may end with escaped whitespace");
            pos += 2;
            has_endline := basic[pos-1] == "\n";
            while (pos < basic.count) && ( basic[pos] == " " || basic[pos] == "\t" || basic[pos] == "\r" || basic[pos] == "\n") {
                has_endline |= basic[pos] == "\n";
                pos += 1;
            }
            if !has_endline { return_with_error_line(source, basic_token.loc, "Escaped whitespace must be at the end of a line"); }
        case "u"; #through;
        case "U";
            num_digits: s32 = xx ifx basic[pos + 1] == "u" then 4 else 8;
            pos += 2;

            if pos + num_digits > basic.count {return_with_error_line(source, basic_token.loc, "Expected % characters in the unicode escape sequence", num_digits); }
            unicode_hex_str := slice(basic, pos, num_digits);
            hex_value, ok, remainder := string_to_int_checked(unicode_hex_str, 16, u32);
            if !ok || remainder.count != 0 { return_with_error_line(source, basic_token.loc, "not valid unicode"); } // TODO improve loc, including \n

            utf8_slice := string.{4, buffer.data + buffer.count};
            Unicode.character_utf32_to_utf8(hex_value, *utf8_slice);
            if hex_value > 0x0010FFFF || !is_valid_utf8(utf8_slice) { return_with_error_line(source, basic_token.loc, "Invalid UTF-8 sequence in escape sequence."); }
            buffer.count += utf8_slice.count; // UTF-8 bytes are already in the buffer at the right position
            pos += num_digits;
        case; return_with_error_line(source, basic_token.loc, "Invalid escape sequence."); // TODO improve loc, including \n
        }
    }
    return true, buffer;
}

Scope :: struct {
    source: string;
    tokens: []Token;
    pos: s64 = 0;
    remaining_key: string = "";
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
        case .LITERAL; return true, eat_token(scope);     // A quoted token cannot have sub-keys
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
    char_pos :s32= cast(s32, original.str.count - scope.remaining_key.count); // Assumes remaining_key is a suffix of original.str
    next:, scope.remaining_key = split_from_left_incl(scope.remaining_key, ".");
    if scope.remaining_key.count == 0 { eat_token(scope); }                   // Consume the token once all parts have been eaten
    if next == "." { return true, Token.{type=Token.Type.DOT, loc=Location.{original.loc.line, char_pos}}; }
    if !is_bare_key(next) { return_with_error_line(scope.source, .{original.loc.line, char_pos}, "Invalid key % Bare keys may contain only A-Za-z0-9_- otherwise use quotes", next); }
    return true, Token.{type=Token.Type.LITERAL, str=next, loc=Location.{original.loc.line, char_pos}};
}
eat_expected_key :: (scope: *Scope, expected: Token.Type) -> ok:=false, key:Token=.{} {
    ok, token := eat_key(scope); if !ok return;
    if token.type != expected { return_with_error_line(scope.source, token.loc, "Expected %, got %", expected, token.type); }
    return true, token;
}
eat_scope :: (scope: *Scope, edible: Token) -> Scope {
    assert(edible.type == .SCOPE_BRACE || edible.type == .SCOPE_BRACKET || edible.type == .SCOPE_DOUBLE_BRACKET);
    scope.pos += edible.scope.count + 1;
    return Scope.{scope.source, edible.scope, 0, ""};
}
// * sub_scope does not contain the scope_end token
eat_scope_until_assign :: (scope: *Scope) -> ok:=false, sub_scope:Scope=.{} {
    start_pos := scope.pos;
    while has_next(scope) {
        if eat_token(scope).type == .ASSIGN {
            return true, Scope.{scope.source, array_view(scope.tokens, start_pos, scope.pos - start_pos - 1), 0, ""};
        }
    }
    return_with_error_line(scope.source, scope.tokens[start_pos].loc, "Unexpected end of scope. Expected =");
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
string_to_int_checked :: (s: string, base := 10, $T := int) -> result: T, ok: bool, remainder: string {
    assert(base == 16 || base <= 10);
    if !s return 0, false, "";

    sign : T = 1;
    #if #run type_info(T).signed {
        if s[0] == "-" {
            sign = -1;
            advance(*s, 1);
        } else if s[0] == "+" {
            advance(*s, 1);
        }
    }

    sum: T = 0;
    cursor := 0;

    if base == 16 {
        while cursor < s.count {
            c := s[cursor];

            value: u8 = ---;
            if is_digit(c)                   { value = c - "0"; }
            else if (c >= "a") && (c <= "f") { value = c - "a" + 10; }
            else if (c >= "A") && (c <= "F") { value = c - "A" + 10; }
            else { break; }

            sum *= cast(T, base);
            sum += sign * cast(T, value);
            if sum != 0 && ((sum < 0) ^ (sign < 0)) { return 0, false, s; }

            cursor += 1;
        }
    } else {
        while cursor < s.count {
            c := s[cursor];
            if !is_digit(c) break;

            digit := c - "0";
            if digit >= base break;

            sum *= cast(T,  base);
            sum += sign*cast(T, digit);
            if sum != 0 &&((sum < 0) ^ (sign < 0)) { return 0, false, s; }

            cursor += 1;
        }
    }

    success := (cursor != 0);
    advance(*s, cursor);

    return sum, success, s;
}

is_bare_key :: (str: string) -> bool {
    for str  if !is_alnum(it) && it != "-" return false;
    return str.count > 0;
}

// For validation purposes we use padding space in Value to store some metadata
// We do not want to expose these to users.
DefineMethod :: enum u8 {
    VALUE      :: 0; // inline-table {}, array [] or literal
    HEADER     :: 1; // [table], [[array of tables]] or the root table
    DOTTED_KEY :: 2; // If it appeared in a dotted key chain of a key = value pair
}
define :: inline (value: *Value, $method: DefineMethod) {
    value.parsing_meta[xx method] = xx true;
}
is_defined :: inline (value: *Value, $method: DefineMethod) -> bool {
    return xx value.parsing_meta[xx method];
}
// Index into context.toml.index_maps array, default -1 means no index map
index_map_id :: inline (value: *Value) -> s32 {
    return cast(*s32, *value.parsing_meta[3]).*;
}
index_map_id :: inline (value: *Value, new_id: s32) {
    cast(*s32, *value.parsing_meta[3]).* = new_id;
}

// Get or insert key with index map
find_or_insert_key :: (table: *Value, key: string) -> is_new:bool, table:*Value {
    assert(table.kind == .TABLE);

    if table.table.count < context.toml.index_threshold {
        for table.table if it.key == key { return false, *it.value; } // Linear search for small tables
        array_add(*table.table, KeyValue.{key=key, value=.{}});       // Add new key value
        return true, *peek_pointer(table.table).value;                // Return the value that was added to the end
    } else if table.table.count == context.toml.index_threshold {
        new_index_map: Table(string, s64);                               // Create an index map for a table when it reaches the threshold
        for table.table { table_add(*new_index_map, it.key, it_index); } // Populate the hash table with existing keys
        index_map_id(table, xx context.toml.index_maps.count);           // Set the ID into the index map id
        array_add(*context.toml.index_maps, new_index_map);              // Add the new index map to the context
    }

    assert(index_map_id(table) >= 0);
    index_map         := *context.toml.index_maps[index_map_id(table)];
    key_index, is_new := find_or_add(index_map, key);
    if !is_new { return false, *table.table[key_index.*].value; } // Return the found existing value

    key_index.* = table.table.count;                        // The new index of the key into the table
    array_add(*table.table, KeyValue.{key=key, value=.{}}); // Add new key value
    return true, *peek_pointer(table.table).value;          // Return the value that was added to the end
}

// Uses index when available, if index_map_id is set entry must exist in index_maps
table_find_value_by_key :: (table: *Value, key: string) -> found:=false, table:*Value=null {
    assert(table.kind == .TABLE);
    if context.toml.index_maps.count == 0 || index_map_id(table) < 0 { // Linear search for small tables
        for table.table if it.key == key { return true, *it.value; }
    } else {                                                           // Use hash lookup for large tables
        index_map    := *context.toml.index_maps[index_map_id(table)];
        found, index := table_find(index_map, key);
        if found { return true, *table.table[index].value; }
    }
    return false;
}
