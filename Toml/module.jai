// Does not support:
// - Basic strings (escaped strings)
// - Multi-line strings
// - Date / Time
// - Values may not overwrite / append to previous ones
// - Full toml validation like endlines in an inline table
// - Error propagation

main :: () {
    contents := read_entire_file("toml.toml");
    tokens  := tokenize(contents);
    scope  := Scope.{contents, tokens, 0, ""};
    toml    := parse(scope);
    print_value(toml);
}

Value_Type :: enum u8 {
    BOOL;
    INT;
    FLOAT;
    STRING;
    ARRAY;
    TABLE;
}

Value :: struct {
    type: Value_Type;
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

// At top level we can expect (keys, [keys], [[keys]])
parse :: (scope: Scope) -> root_table:Value {
    // We use a Root instead of just an array to make sure overlapping keys are handled in parse_key
    root_table := KeyValue.{"*ROOT*", Value.{type=.TABLE}}; // root name should be something not possible in TOML
    current_table := *root_table.value;
    while has_next(scope) {
        token := peak_next(scope);
        if token.type == Token_Type.SCOPE_BRACKET {
            current_table = parse_header(*root_table.value, sub(scope, token.scope));
            eat_scope(*scope, token);
        } else { // Parse key value pair
            keys_scope := eat_scope_until(*scope, Token_Type.ASSIGN);
            _, leaf_value := parse_key(current_table, keys_scope);
            <<leaf_value = parse_value(leaf_value, *scope);
        }
    }
    return root_table.value;
}


#scope_file

parse_header :: (root_table: *Value, scope: Scope) -> *Value {
    // log("parse_header");
    if !has_next(scope) || peak_next(scope).type != Token_Type.SCOPE_BRACKET{
        // Parse table header
        _, current_table, is_new := parse_key(root_table, scope);
        if !is_new && current_table.type != Value_Type.TABLE {
            exit_with_error_line(scope.source, last(scope).loc, "Cannot use key as Tables as it already has a value: %", current_table.type);
        }
        return current_table;
    }
    // Parse array of tables header
    aot_scope := sub(scope, eat_next(*scope).scope);
    if scope.tokens.count > aot_scope.tokens.count + 1 {
        error_token:= scope.tokens[1 + aot_scope.tokens.count];
        exit_with_error_line(scope.source, error_token.loc, "Unexpected % in Array of Tables header", error_token.type);
    }

    _, current_table, is_new := parse_key(root_table, aot_scope);
    if !is_new && current_table.type != Value_Type.ARRAY {
        exit_with_error_line(aot_scope.source, last(aot_scope).loc, "Cannot use key as Array of Tables as it already has a value: %", current_table.type);
    }

    current_table.type = Value_Type.ARRAY;
    array_add(*current_table.array, Value.{type=.TABLE});
    return *current_table.array[current_table.array.count-1];
}


// parse key.key.key.etc =
parse_key :: (parent: *Value, scope: Scope) -> root:KeyValue, leaf:*Value, leaf_is_new:bool {
    // log("parse_key");
    if !has_next(scope) { exit_with_error("Unexpected end of scope while parsing key"); }
    token := eat_next_for_keys(*scope);
    if token.type != Token_Type.QUOTED { exit_with_error_line(scope.source, token.loc, "Key cannot start with a %", token.type); }

    local_root : KeyValue;
    local_root.key = token.str;
    local_root.value = Value.{type=.TABLE};

    current_table := *local_root.value;
    current_is_new := true;
    if parent != null {
        if parent.type != Value_Type.TABLE { exit_with_error("Cannot use key as table as it already has a value: %", parent.type); } // TODO print_value
        current_is_new =, index := array_add_if_unique(*parent.table, local_root);
        current_table = *parent.table[index].value;
    }

    while has_next(scope) {
        token = eat_next_for_keys(*scope);
        if token.type != Token_Type.DOT { exit_with_error_line(scope.source, token.loc, "Expected DOT, got %", token.type); }
        if !has_next(scope) { exit_with_error_line(scope.source, last_eaten(scope).loc, "Key is not allowed to end with a dot"); }
        token = eat_next_for_keys(*scope);
        if token.type != Token_Type.QUOTED { exit_with_error_line(scope.source, token.loc, "Expected KEY, got %", token.type); }

        if current_table.type == Value_Type.ARRAY { // This is an Array of Tables header that we are going to add into
            assert(current_table.array.count > 0); // How would this be possible
            current_table = *current_table.array[current_table.array.count-1];
        }
        if current_table.type != Value_Type.TABLE { exit_with_error("Cannot use key as table it already has a value: %", current_table.type); }
        current_is_new=, index := array_add_if_unique(*current_table.table, KeyValue.{token.str, Value.{type=.TABLE}});
        current_table = *current_table.table[index].value;
    }
    return local_root, current_table, current_is_new;
}

parse_value :: (current_table: *Value, scope: *Scope) -> value:Value { // TODO only assign value if key is empty table
    // log("parse_value");
    if !has_next(scope) { exit_with_error("Unexpected end of file while parsing value"); }

    token := peak_next(scope);
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
        eat_next(scope); // Might be 2 if date time
        return literal;
    }
}

parse_inline_table :: (current_table: *Value, scope: Scope) -> table:Value {
    // log("parse_inline_table");
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    table_root := KeyValue.{"*TABLE_ROOT*", Value.{type=.TABLE}}; // root name should be something not possible in TOML
    if current_table == null { current_table = *table_root.value; }
    while has_next(scope) {
        keys_scope := eat_scope_until(*scope, Token_Type.ASSIGN);
        _, leaf_value := parse_key(current_table, keys_scope);
        <<leaf_value = parse_value(leaf_value, *scope);

        // Inline tables are not allowed to have trailing commas
        if has_next(scope, 2) { eat_expected(*scope, Token_Type.COMMA); } // TODO improve error message
    }
    return <<current_table;
}

parse_array :: (scope: Scope) -> array:Value {
    // log("parse_array");
    values : [..]Value;
    while has_next(scope) {
        value := parse_value(null, *scope);
        array_add(*values, value);
        if has_next(scope) { eat_expected(*scope, Token_Type.COMMA); }
    }
    return Value.{type=.ARRAY, array=values};
}

parse_literal :: (scope: *Scope) -> Value {
    // log("parse_literal %", token.type);
    token := peak_next(scope);
    if token.type == {
    case .QUOTED;  return Value.{type=.STRING, string_value=token.str};
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
            // TODO detect leading zeros error
            int_value, success, remainder := string_to_int(clean_str, 10, s64);
            if success && remainder.count == 0 { return Value.{type=.INT, int_value=int_value}; }
        }

        // Parse float
        // TODO detect illegal floats: .7  7.  3.e+20 ... leading zeros
        float_value, success, remainder := string_to_float64(clean_str);
        if success && remainder.count == 0 { return Value.{type=.FLOAT, float_value=float_value}; }
        if token.str == "inf" || token.str == "+inf"  { return Value.{type=.FLOAT, float_value=FLOAT64_INFINITY}; }
        if token.str == "-inf"                        { return Value.{type=.FLOAT, float_value=-FLOAT64_INFINITY}; }
        if token.str == "nan" || token.str == "+nan" { return Value.{type=.FLOAT, float_value=FLOAT64_NAN}; }
        if token.str == "-nan"                        { return Value.{type=.FLOAT, float_value=-FLOAT64_NAN}; }

        // if date, check if next token is time seperated by single space: 1979-05-27 07:32:00Z

        exit_with_error_line(scope.source, token.loc, "Unable to parse literal %", token.str);
    case;
        exit_with_error_line(scope.source, token.loc, "Unexpected token %, expected a value", token.type);
    }
    return Value.{};
}

Scope :: struct {
    source: string;
    tokens: []TOML_Token;
    pos: s64 = 0;
    remaining_key: string;
}
has_next :: (scope: Scope, count:=1) -> bool {
    return scope.pos + count -1 < scope.tokens.count;
}
peak_next :: (scope: Scope) -> TOML_Token {
    return scope.tokens[scope.pos];
}
eat_next :: (scope: *Scope) -> TOML_Token {
    token := peak_next(scope);
    scope.pos += 1; // Do we want to eat scope here?
    return token;
}

eat_next_for_keys :: (scope: *Scope) -> TOML_Token {
    if scope.remaining_key.count == 0 {
        token := peak_next(scope);
        if token.type == {
        case .QUOTED; return eat_next(scope);
        case .RAW;    scope.remaining_key = token.str;
        case;         exit_with_error_line(scope.source, token.loc, "Expected key, got %", token.type);
        }
    }
    original := peak_next(scope);
    char_num := cast(s32) inline find_index_from_right(original.str, scope.remaining_key);
    next:, scope.remaining_key = split_from_left_incl(scope.remaining_key, #char ".");
    if scope.remaining_key.count == 0 { eat_next(scope); }
    if next == "." { return TOML_Token.{type=Token_Type.DOT, loc=Location.{original.loc.line, char_num}}; }
    else           { return TOML_Token.{type=Token_Type.QUOTED, str=next, loc=Location.{original.loc.line, char_num}}; }
}

last_eaten :: (scope: Scope) -> TOML_Token {
    return scope.tokens[scope.pos-1];
}
last :: (scope: Scope) -> TOML_Token {
    return scope.tokens[scope.tokens.count-1];
}
sub :: (scope: Scope, tokens: []TOML_Token) -> Scope {
    return Scope.{scope.source, tokens, 0, ""};
}

eat_scope :: (scope: *Scope, edible: TOML_Token) {
    assert(edible.type == .SCOPE_BRACE || edible.type == .SCOPE_BRACKET);
    scope.pos += edible.scope.count + 1;
}

eat_expected :: (scope: *Scope, expected: Token_Type) {
    token := eat_next(scope);
    if token.type != expected { exit_with_error_line(scope.source, token.loc, "Expected %, got %", expected, token.type); }
}

// * sub_scope does not contain the scope_end token
eat_scope_until :: (scope: *Scope, scope_end: Token_Type) -> sub_scope:Scope {
    start_pos := scope.pos;
    while has_next(scope) { // TODO impl for for Scope
        if eat_next(scope).type == scope_end {
            return Scope.{scope.source, array_view(scope.tokens, start_pos, scope.pos - start_pos - 1), 0, ""};
        }
    }
    exit_with_error_line(scope.source, scope.tokens[start_pos].loc, "Unexpected end of scope. Expected %", scope_end);
    return scope;
}

get_line :: (data: string, line_number: s32) -> line: string, found:bool {
    line: string;
    found: bool;
    for 1..line_number { line, found = consume_next_line(*data); }
    return line, found;
}

exit_with_error :: (format: string, arguments: .. Any) {
    log_error(format, ..arguments);
    exit(1);
}
exit_with_error_line :: (source: string, loc: Location, format: string, arguments: .. Any) {
    #import "Text_File_Handler";
    line, found := get_line(source, loc.line);
    if !found {
        log_error("Failed to read line % from file", loc.line);
        exit(1);
    }
    message := tprint(format, ..arguments);
    log_error("Line % Char %: %", loc.line, loc.character, message);
    log_error(line);

    // print ^^ under the char number
    builder: String_Builder;
    for 1..loc.character-1 { append(*builder, #char " "); }
    append(*builder, #char "^");
    log_error(builder_to_string(*builder));

    exit(1);
}

print_value :: (value : Value, indent:="") {
    if value.type == {
    case .STRING; print("%", value.string_value);
    case .INT; print("%", value.int_value);
    case .FLOAT; print("%", value.float_value);
    case .BOOL; print("%", value.bool_value);
    case .ARRAY;
        print("[\n");
        new_indent := tprint("%  ", indent);
        for val: value.array {
            print("%", new_indent);
            print_value(val, new_indent);
            print(",\n");
        }
        print("%]", indent);
    case .TABLE;
        print("{\n");
        new_indent := tprint("%  ", indent);
        for keyval: value.table {
            print("%0% ", new_indent, keyval.key);
            if keyval.type != .TABLE { print("= "); }
            print_value(keyval.value, new_indent);
            print("\n");
        }
        print("%}", indent);
    }
}

// .   -> `.`  ``
// ab  -> `ab` ``
//     -> ``   ``
// .ab -> `.`  `ab`
// a.b -> `a`  `.b`
// ab. -> `ab` `.`
split_from_left_incl :: (s: string, separator: u8) -> (left: string, right: string) {
    index := inline find_index_from_left(s, separator);
    if index == -1  return s, "";
    if index == 0  index = 1;
    return slice(s, 0, index), slice(s, index, s.count - index);
}

operator == :: inline (a: KeyValue, b: KeyValue) -> bool {
    // Not a full comparison, just used for array_add_if_unique
    // Consider poking it only where needed
    return a.key == b.key;
}

#load "lexer.jai";
using Basic :: #import "Basic";
#poke_name Basic operator==;
#import "File";
#import "String";
#import "Math";
