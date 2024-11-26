// Does not support:
// - Date / Time
// - Rejecting all control characters
// - Rejecting values that overwrite / append to previous ones
// - Full toml validation like endlines in an inline table
// - Error propagation

Value :: struct {
    Type :: enum u8 {
        BOOL;
        INT;
        FLOAT;
        STRING;
        ARRAY;
        TABLE;
    }
    type: Type;
    union {
        bool_value  : bool;
        int_value   : s64;
        float_value : float64;
        string_value: string;
        array       : [..]Value;
        table       : [..]KeyValue;
    };
}
KeyValue :: struct {
    key        :  string;
    using value:  Value;
}

parse :: (contents: string) -> root_table:Value {
    tokens := tokenize(contents,, allocator=temp);
    scope  := Scope.{contents, tokens, 0, ""};

    // At top level we can expect (keys, [keys], [[keys]])
    root_table := Value.{type=.TABLE, table=resizable(KeyValue.[])};
    current_table := *root_table;
    while has_next(scope) {
        token := peak_token(scope);
        if token.type == Token.Type.SCOPE_BRACKET {
            current_table = parse_header(*root_table, sub(scope, token.scope));
            eat_scope(*scope, token);
        } else { // Parse key value pair
            keys_scope := eat_scope_until(*scope, Token.Type.ASSIGN);
            _, leaf_value := parse_key(current_table, keys_scope);
            <<leaf_value = parse_value(leaf_value, *scope);
        }
    }
    return root_table;
}

copy :: (value: Value) -> Value {
    if #complete value.type == {
    case .BOOL; #through;
    case .INT;  #through;
    case .FLOAT;  return value;
    case .STRING; return Value.{type=value.type, string_value=copy_string(value.string_value)};
    case .ARRAY;
        output:= Value.{type=.ARRAY, array=resizable(Value.[])};
        array_copy(*output.array, value.array);
        return output;
    case .TABLE;
        output:= Value.{type=.TABLE, table=resizable(KeyValue.[])};
        array_copy(*output.table, value.table);
        return output;
    }
}

#scope_file

parse_header :: (root_table: *Value, scope: Scope) -> *Value {
    if !has_next(scope) || peak_token(scope).type != Token.Type.SCOPE_BRACKET{
        // Parse table header
        _, current_table, is_new := parse_key(root_table, scope);
        if !is_new && current_table.type != Value.Type.TABLE {
            exit_with_error_line(scope.source, last(scope).loc, "Cannot use key as Tables as it already has a value: %", current_table.type);
        }
        return current_table;
    } else {
        // Parse array of tables header
        aot_scope := sub(scope, eat_token(*scope).scope);
        if scope.tokens.count > aot_scope.tokens.count + 1 { // No tokens between the closing brackets `]]` allowed
            error_token:= scope.tokens[1 + aot_scope.tokens.count];
            exit_with_error_line(scope.source, error_token.loc, "Unexpected % in Array of Tables header", error_token.type);
        }

        _, current_table, is_new := parse_key(root_table, aot_scope);
        if current_table.type != .ARRAY {
            if !is_new { exit_with_error_line(aot_scope.source, last(aot_scope).loc, "Cannot use key as Array of Tables as it already has a value: %", current_table.type); }
            <<current_table = .{type=.ARRAY, array=resizable(Value.[])};
        }
        array_add(*current_table.array, Value.{type=.TABLE, table=resizable(KeyValue.[])});
        return *current_table.array[current_table.array.count-1];
    }
}


// parse key. key.`key`."etc"
parse_key :: (parent: *Value, scope: Scope) -> root:KeyValue, leaf:*Value, leaf_is_new:bool {
    if !has_next(scope) { exit_with_error("Unexpected end of scope while parsing key"); }
    token := eat_key_token(*scope);
    if token.type != Token.Type.QUOTED { exit_with_error_line(scope.source, token.loc, "Key cannot start with a %", token.type); }

    local_root := KeyValue.{key=token.str, value=Value.{type=.TABLE, table=resizable(KeyValue.[])}};
    current_table := *local_root.value;
    current_is_new := true;
    if parent != null {
        if parent.type != Value.Type.TABLE { exit_with_error("Cannot use key as table as it already has a value: %", parent.type); } // TODO print_value
        current_is_new =, index := array_add_copy_if_unique(*parent.table, local_root);
        current_table = *parent.table[index].value;
    }

    while has_next(scope) {
        token = eat_key_token(*scope);
        if token.type != Token.Type.DOT { exit_with_error_line(scope.source, token.loc, "Expected DOT, got %", token.type); }
        if !has_next(scope) { exit_with_error_line(scope.source, last(scope).loc, "Key is not allowed to end with a dot"); }
        token = eat_key_token(*scope);
        if token.type != Token.Type.QUOTED { exit_with_error_line(scope.source, token.loc, "Expected KEY, got %", token.type); }

        if current_table.type == Value.Type.ARRAY { // This is an Array of Tables header that we are going to add into
            assert(current_table.array.count > 0); // How would this be possible
            current_table = *current_table.array[current_table.array.count-1];
        }
        if current_table.type != Value.Type.TABLE { exit_with_error("Cannot use key as table it already has a value: %", current_table.type); }
        current_is_new=, index := array_add_copy_if_unique(*current_table.table, KeyValue.{token.str, Value.{type=.TABLE, table=resizable(KeyValue.[])}});
        current_table = *current_table.table[index].value;
    }
    return local_root, current_table, current_is_new;
}

parse_value :: (current_table: *Value, scope: *Scope) -> value:Value { // TODO only assign value if key is empty table
    if !has_next(scope) { exit_with_error("Unexpected end of file while parsing value"); }

    token := peak_token(scope);
    if token.type == {
    case .SCOPE_BRACE;
        table := parse_inline_table(current_table, sub(scope, token.scope));
        eat_scope(scope, token);
        return table;
    case .SCOPE_BRACKET;
        array := parse_array(sub(scope, token.scope));
        eat_scope(scope, token);
        return array;
    case;
        literal := parse_literal(scope);
        return literal;
    }
}

parse_inline_table :: (current_table: *Value, scope: Scope) -> table:Value {
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    table_root := Value.{type=.TABLE, table=resizable(KeyValue.[])};
    if current_table == null { current_table = *table_root; }
    while has_next(scope) {
        keys_scope := eat_scope_until(*scope, Token.Type.ASSIGN);
        _, leaf_value := parse_key(current_table, keys_scope);
        <<leaf_value = parse_value(leaf_value, *scope);

        // Inline tables are not allowed to have trailing commas
        if has_next(scope, 2) { eat_expected(*scope, Token.Type.COMMA); } // TODO improve error message
    }
    return <<current_table;
}

parse_array :: (scope: Scope) -> array:Value {
    values : [..]Value;
    while has_next(scope) {
        value := parse_value(null, *scope);
        array_add(*values, value);
        if has_next(scope) { eat_expected(*scope, Token.Type.COMMA); }
    }
    return Value.{type=.ARRAY, array=values};
}

parse_literal :: (scope: *Scope) -> Value {
    token := eat_token(scope);
    if token.type == {
    case .QUOTED;       #through;
    case .QUOTED_MULTI; return Value.{type=.STRING, string_value=copy_string(token.str)};
    case .RAW;
        // Parse boolean
        if token.str == "true" { return Value.{type=.BOOL, bool_value=true}; }
        if token.str == "false" { return Value.{type=.BOOL, bool_value=false}; }

        // Parse integer
        clean_str := replace(token.str, "_", ""); // TODO make number specific to check before and after _ is digit / hex etc
        if begins_with(token.str, "0x") {
            advance(*clean_str, 2);
            hex_value, success, remainder := string_to_int(clean_str, 16, s64);
            if success && remainder.count == 0 { return Value.{type=.INT, int_value=hex_value}; }
        } else if begins_with(token.str, "0b") {
            advance(*clean_str, 2);
            bin_value, success, remainder := string_to_int(clean_str, 2, s64);
            if success && remainder.count == 0 { return Value.{type=.INT, int_value=bin_value}; }
        } else if begins_with(token.str, "0o") {
            advance(*clean_str, 2);
            oct_value, success, remainder := string_to_int(clean_str, 8, s64);
            if success && remainder.count == 0 { return Value.{type=.INT, int_value=oct_value}; }
        } else {
            // TODO detect leading zeros error, note 00 can be the start of a time
            int_value, success, remainder := string_to_int(clean_str, 10, s64);
            if success && remainder.count == 0 { return Value.{type=.INT, int_value=int_value}; }
        }

        // Parse float
        // TODO detect illegal floats: .7  7.  3.e+20 ... leading zeros
        float_value, success, remainder := string_to_float64(clean_str);
        if success && remainder.count == 0 { return Value.{type=.FLOAT, float_value=float_value}; }
        if token.str == "inf" || token.str == "+inf" { return Value.{type=.FLOAT, float_value=FLOAT64_INFINITY}; }
        if token.str == "-inf"                       { return Value.{type=.FLOAT, float_value=-FLOAT64_INFINITY}; }
        if token.str == "nan" || token.str == "+nan" { return Value.{type=.FLOAT, float_value=FLOAT64_NAN}; }
        if token.str == "-nan"                       { return Value.{type=.FLOAT, float_value=-FLOAT64_NAN}; }

        // if date, check if next token is time seperated by single space: 1979-05-27 07:32:00Z

        exit_with_error_line(scope.source, token.loc, "Unable to parse literal %", token.str);
    case;
        exit_with_error_line(scope.source, token.loc, "Unexpected token %, expected a value", token.type);
    }
    return Value.{};
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
peak_token :: (scope: Scope) -> Token {
    return scope.tokens[scope.pos];
}
eat_token :: (scope: *Scope) -> Token {
    token := peak_token(scope);
    scope.pos += 1;
    return token;
}
eat_key_token :: (scope: *Scope) -> Token {
    original := peak_token(scope);
    if scope.remaining_key.count == 0 {
        if original.type == {
        case .QUOTED; return eat_token(scope);            // A quoted token cannot have sub-keys
        case .RAW;    scope.remaining_key = original.str; // A raw token may contain several dot separated keys
        case .QUOTED_MULTI; exit_with_error_line(scope.source, original.loc, "Cannot use multi-line strings as key");
        case .DOT;          assert(false, "Parser expects lexer to give `.` as RAW, not as DOT");
        case;               exit_with_error_line(scope.source, original.loc, "Expected key, got %", original.type);
        }
    }
    // Handling potentially dot separated RAW key
    char_num := cast(s32) inline find_index_from_right(original.str, scope.remaining_key);
    next:, scope.remaining_key = split_from_left_incl(scope.remaining_key, #char ".");
    if scope.remaining_key.count == 0 { eat_token(scope); }
    if next == "." { return Token.{type=Token.Type.DOT, loc=Location.{original.loc.line, char_num}}; }
    else           { return Token.{type=Token.Type.QUOTED, str=next, loc=Location.{original.loc.line, char_num}}; }
}
eat_scope :: (scope: *Scope, edible: Token) {
    assert(edible.type == .SCOPE_BRACE || edible.type == .SCOPE_BRACKET);
    scope.pos += edible.scope.count + 1;
}
eat_expected :: (scope: *Scope, expected: Token.Type) {
    token := eat_token(scope);
    if token.type != expected { exit_with_error_line(scope.source, token.loc, "Expected %, got %", expected, token.type); }
}
// * sub_scope does not contain the scope_end token
eat_scope_until :: (scope: *Scope, scope_end: Token.Type) -> sub_scope:Scope {
    start_pos := scope.pos;
    while has_next(scope) { // TODO impl for for Scope
        if eat_token(scope).type == scope_end {
            return Scope.{scope.source, array_view(scope.tokens, start_pos, scope.pos - start_pos - 1), 0, ""};
        }
    }
    exit_with_error_line(scope.source, scope.tokens[start_pos].loc, "Unexpected end of scope. Expected %", scope_end);
    return scope;
}
sub :: (scope: Scope, tokens: []Token) -> Scope {
    return Scope.{scope.source, tokens, 0, ""};
}
last :: (scope: Scope) -> Token {
    return scope.tokens[scope.tokens.count-1];
}

// .   -> `.`  ``   // .ab -> `.`  `ab`
// ab  -> `ab` ``   // a.b -> `a`  `.b`
//     -> ``   ``   // ab. -> `ab` `.`
split_from_left_incl :: (s: string, separator: u8) -> (left: string, right: string) {
    index := inline find_index_from_left(s, separator);
    if index == -1  return s, "";
    if index == 0  index = 1; // Starts with separator
    return slice(s, 0, index), slice(s, index, s.count - index);
}

array_add_copy_if_unique :: (array: *[..]KeyValue, item: KeyValue) -> is_new:bool, index:s64 {
    found, index := array_find(<<array, item);
    if found return false, index;

    array_add(array, item);
    (<<array)[array.count-1].key = copy_string(item.key);
    return true, array.count-1;
}

operator == :: inline (a: KeyValue, b: KeyValue) -> bool {
    // Not a full comparison, just used for array_find
    return a.key == b.key;
}

#load "lexer.jai";
using Basic :: #import "Basic";
#poke_name Basic operator==;
#import "File";
#import "String";
#import "Math";
