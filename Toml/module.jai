// Does not support:
// - Quoted key, keys with `-`, keys starting with a number
// - Basic strings (escaped strings)
// - Multi-line strings
// - Float values
// - Integers starting with +/-, hex, octal, binary
// - Date / Time
// - Full toml validation like endlines in an inline table
// - Error propagation

main :: () {
    contents = read_entire_file("toml.toml");
    tokens  := tokenize(contents);
    toml    := parse(tokens);
    print_value(toml);
}

Value_Type :: enum u8 {
    BOOL;
    INT;
    STRING;
    ARRAY;
    TABLE;
}

Value :: struct {
    type: Value_Type;
    union {
        bool_value  : bool;
        int_value   : s64;
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
parse :: (tokens: []TOML_Token) -> root_table:Value {
    scope := Scope.{tokens, 0};
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

contents : string; // TODO

parse_header :: (root_table: *Value, scope: Scope) -> *Value {
    // log("parse_header");
    if !has_next(scope) || peak_next(scope).type != Token_Type.SCOPE_BRACKET{
        // Parse table header
        _, current_table, is_new := parse_key(root_table, scope);
        if !is_new && current_table.type != Value_Type.TABLE {
            log_error("Cannot use key as Tables as it already has a value: %", current_table.type);
            print_issue(last(scope).line, last(scope).character);
            exit(1);
        }
        return current_table;
    }
    // Parse array of tables header
    aot_scope := sub(scope, eat_next(*scope).scope);
    if scope.tokens.count > aot_scope.tokens.count + 1 {
        error_token:= scope.tokens[1 + aot_scope.tokens.count];
        log_error("Unexpected % in Array of Tables header", error_token.type);
        print_issue(error_token.line, error_token.character);
        exit(1);
    }

    _, current_table, is_new := parse_key(root_table, aot_scope);
    if !is_new && current_table.type != Value_Type.ARRAY {
        log_error("Cannot use key as Array of Tables as it already has a value: %", current_table.type);
        print_issue(last(aot_scope).line, last(aot_scope).character);
        exit(1);
    }

    current_table.type = Value_Type.ARRAY;
    array_add(*current_table.array, Value.{type=.TABLE});
    return *current_table.array[current_table.array.count-1];
}


// parse key.key.key.etc =
parse_key :: (parent: *Value, scope: Scope) -> root:KeyValue, leaf:*Value, leaf_is_new:bool {
    // log("parse_key");
    if !has_next(scope) {
        log_error("Unexpected end of scope while parsing key"); // todo simplify
        exit(1);
    }
    token := eat_next(*scope);
    if token.type != Token_Type.KEY {
        log_error("Expected key, got %", token.type);
        print_issue(token.line, token.character);
        exit(1);
    }
    local_root : KeyValue;
    local_root.key = token.string_value;
    local_root.value = Value.{type=.TABLE};

    current_table := *local_root.value;
    current_is_new := true;
    if parent != null {
        if parent.type != Value_Type.TABLE {
            log_error("Cannot use key as table as it already has a value: %", parent.type);
            exit(1);
        }
        current_is_new =, index := array_add_if_unique(*parent.table, local_root);
        current_table = *parent.table[index].value;
    }

    while has_next(scope) {
        eat_expected(*scope, Token_Type.DOT);
        if !has_next(scope) {
            log_error("Key is not allowed to end with a dot");
            print_issue(last_eaten(scope).line, last_eaten(scope).character);
            exit(1);
        }
        token = eat_next(*scope);
        if token.type != Token_Type.KEY {
            log_error("Expected key, got %\n", token.type);
            print_issue(token.line, token.character);
            exit(1);
        }
        if current_table.type != Value_Type.TABLE {
            log_error("Cannot use key as table it already has a value: %", current_table.type);
            exit(1);
        }
        current_is_new, index := array_add_if_unique(*current_table.table, KeyValue.{token.string_value, Value.{type=.TABLE}});
        current_table = *current_table.table[index].value;
    }
    return local_root, current_table, current_is_new;
}

parse_value :: (current_table: *Value, scope: *Scope) -> value:Value { // TODO only assign value if key is empty table
    // log("parse_value");
    if !has_next(scope) {
        log_error("Unexpected end of file while parsing value");
        exit(1);
    }

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
        literal := parse_literal(token);
        eat_next(scope);
        return literal;
    }
}

parse_inline_table :: (current_table: *Value, scope: Scope) -> table:Value { // TODO current_table does not need to be a pointer
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

parse_literal :: (token: TOML_Token) -> Value {
    // log("parse_literal %", token.type);
    if token.type == {
    case .BOOLEAN; return Value.{type=.BOOL, bool_value=token.bool_value};
    case .INTEGER; return Value.{type=.INT, int_value=token.int_value};
    case .STRING;  return Value.{type=.STRING, string_value=token.string_value};
    case;
        log_error("Unexpected token %, expected a value", token.type);
        print_issue(token.line, token.character);
        exit(1);
        return Value.{};
    }
}

Scope :: struct {
    tokens: []TOML_Token;
    pos: s64 = 0;
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
last_eaten :: (scope: Scope) -> TOML_Token {
    return scope.tokens[scope.pos-1];
}
last :: (scope: Scope) -> TOML_Token {
    return scope.tokens[scope.tokens.count-1];
}
sub :: (scope: Scope, tokens: []TOML_Token) -> Scope {
    // todo add contents string
    return Scope.{tokens, 0};
}

eat_scope :: (scope: *Scope, edible: TOML_Token) {
    assert(edible.type == .SCOPE_BRACE || edible.type == .SCOPE_BRACKET);
    scope.pos += edible.scope.count + 1;
}

eat_expected :: (scope: *Scope, expected: Token_Type) {
    if eat_next(scope).type != expected {
        token := peak_next(scope);
        log_error("Expected %, got %", expected, token.type);
        print_issue(token.line, token.character);
        exit(1);
    }
}

// * sub_scope does not contain the scope_end token
eat_scope_until :: (scope: *Scope, scope_end: Token_Type) -> sub_scope:Scope {
    start_pos := scope.pos;
    while has_next(scope) { // TODO impl for for Scope
        if eat_next(scope).type == scope_end {
            return Scope.{array_view(scope.tokens, start_pos, scope.pos - start_pos - 1), 0};
        }
    }
    log_error("Unexpected end of scope. Expected %", scope_end);
    print_issue(scope.tokens[start_pos].line, scope.tokens[start_pos].character);
    exit(1);
    return scope;
}

get_line :: (data: string, line_number: s32) -> line: string, found:bool {
    line: string;
    found: bool;
    for 1..line_number { line, found = consume_next_line(*data); }
    return line, found;
}

print_issue:: (line_number: s32, char_number: s32) {
    #import "Text_File_Handler";
    line, found := get_line(contents, line_number);
    if !found {
        log_error("Failed to read line % from file", line_number);
        exit(1);
    }

    log_error("Line % Char %:", line_number, char_number);
    log_error(line);

    // print ^^ under the char number
    builder: String_Builder;
    for 1..char_number-1 { append(*builder, #char " "); }
    append(*builder, #char "^");
    log_error(builder_to_string(*builder));
}

print_value :: (value : Value, indent:="") {
    if value.type == {
    case .STRING; print("%", value.string_value);
    case .INT; print("%", value.int_value);
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
