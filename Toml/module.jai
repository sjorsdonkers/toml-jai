// Does not support:
// - Quoted key, keys with `-`, keys starting with a number
// - Basic strings (escaped strings)
// - Multi-line strings
// - Float values
// - Integers starting with +/-, hex, octal, binary
// - Date / Time
// - Full toml validation like endlines in an inline table

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
    pos := 0;
    // We use a Root instead of just an array to make sure overlapping keys are handled in parse_key
    root_table := KeyValue.{"*ROOT*", Value.{type=.TABLE}}; // root name should be something not possible in TOML
    current_table := *root_table.value;
    while pos < tokens.count {
        if tokens[pos].type == Token_Type.SCOPE_BRACKET {
            current_table = parse_header(*root_table.value, tokens[pos].scope);
            pos += tokens[pos].scope.count + 1;
        } else { // Parse key value pair
            keys_scope := make_scope_until(tokens, pos, Token_Type.ASSIGN);
            _, leaf_value := parse_key(current_table, keys_scope);
            pos += keys_scope.count + 1;
            <<leaf_value, pos = parse_value(leaf_value, tokens, pos);
        }
    }
    return root_table.value;
}


#scope_file

contents : string; // TODO

parse_header :: (root_table: *Value, tokens: []TOML_Token) -> *Value {
    if tokens.count == 0 || tokens[0].type != Token_Type.SCOPE_BRACKET{
        // Parse table header
        _, current_table, is_new := parse_key(root_table, tokens);
        if !is_new && current_table.type != Value_Type.TABLE {
        log_error("Cannot use key as Tables as it already has a value: %", current_table.type);
        print_issue(tokens[tokens.count-1].line, tokens[tokens.count-1].character);
        exit(1);
    }
        return current_table;
    }
    // Parse array of tables header
    aot_tokens := tokens[0].scope;
    if tokens.count > aot_tokens.count + 1 {
        error_token:= tokens[1 + aot_tokens.count];
        log_error("Unexpected % in Array of Tables header", error_token.type);
        print_issue(error_token.line, error_token.character);
        exit(1);
    }

    _, current_table, is_new := parse_key(root_table, aot_tokens);
    if !is_new && current_table.type != Value_Type.ARRAY {
        log_error("Cannot use key as Array of Tables as it already has a value: %", current_table.type);
        print_issue(aot_tokens[aot_tokens.count-1].line, aot_tokens[aot_tokens.count-1].character);
        exit(1);
    }

    current_table.type = Value_Type.ARRAY;
    array_add(*current_table.array, Value.{type=.TABLE});
    return *current_table.array[current_table.array.count-1];
}


// parse key.key.key.etc =
parse_key :: (parent: *Value, tokens: []TOML_Token) -> root:KeyValue, leaf:*Value, leaf_is_new:bool { // Root is weird  if parent is set
    pos := 0;
    if pos >= tokens.count {
        log_error("Unexpected end of scope while parsing key"); // todo simplify
        exit(1);
    }
    if tokens[pos].type != Token_Type.KEY {
        log_error("Expected key, got %\n", tokens[pos].type);
        print_issue(tokens[pos].line, tokens[pos].character);
        exit(1);
    }
    local_root : KeyValue;
    local_root.key = tokens[pos].string_value;
    local_root.value = Value.{type=.TABLE};
    pos += 1;

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

    while pos < tokens.count {
        eat_expected(tokens, *pos, Token_Type.DOT);
        if pos == tokens.count {
            log_error("Key is not allowed to end with a dot");
            print_issue(tokens[pos-1].line, tokens[pos-1].character);
            exit(1);
        }
        if tokens[pos].type != Token_Type.KEY {
            log_error("Expected key, got %\n", tokens[pos].type);
            print_issue(tokens[pos].line, tokens[pos].character);
            exit(1);
        }
        if current_table.type != Value_Type.TABLE {
            log_error("Cannot use key as table it already has a value: %", current_table.type);
            exit(1);
        }
        current_is_new, index := array_add_if_unique(*current_table.table, KeyValue.{tokens[pos].string_value, Value.{type=.TABLE}});
        current_table = *current_table.table[index].value;
        pos += 1;
    }
    return local_root, current_table, current_is_new;
}

parse_value :: (current_table: *Value, tokens: []TOML_Token, pos: s64) -> value:Value, pos:s64 { // TODO only assign value if key is empty table
    if pos >= tokens.count {
        log_error("Unexpected end of file while parsing value");
        exit(1);
    }

    token := tokens[pos];
    if token.type == {
    case .SCOPE_BRACE;
        table := parse_inline_table(current_table, token.scope);
        pos += token.scope.count + 1;
        return table, pos;
    case .SCOPE_BRACKET;
        array := parse_array(token.scope);
        pos += token.scope.count + 1;
        return array, pos;
    case;
        literal := parse_literal(token);
        pos += 1;
        return literal, pos;
    }
}

parse_inline_table :: (current_table: *Value, tokens: []TOML_Token) -> table:Value { // TODO current_table does not need to be a pointer
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    pos := 0;
    table_root := KeyValue.{"*TABLE_ROOT*", Value.{type=.TABLE}}; // TODO root name should be something not possible in TOML
    if current_table == null { current_table = *table_root.value; }
    while pos < tokens.count {
        keys_scope := make_scope_until(tokens, pos, Token_Type.ASSIGN);
        _, leaf_value := parse_key(current_table, keys_scope);
        pos += keys_scope.count + 1;
        <<leaf_value, pos = parse_value(leaf_value, tokens, pos);

        // Inline tables are not allowed to have trailing commas
        if pos+1 < tokens.count { eat_expected(tokens, *pos, Token_Type.COMMA); } // TODO improve error message
    }
    return <<current_table;
}

parse_array :: (tokens: []TOML_Token) -> array:Value {
    pos := 0;
    values : [..]Value;
    while pos < tokens.count {
        value:, pos = parse_value(null, tokens, pos);
        array_add(*values, value);
        if pos == tokens.count { break; }
        eat_expected(tokens, *pos, Token_Type.COMMA);
    }
    return Value.{type=.ARRAY, array=values};
}

parse_literal :: (token: TOML_Token) -> Value {
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

make_scope_until :: (tokens: []TOML_Token, start_pos: int, scope_end: Token_Type) -> []TOML_Token {
    for pos: start_pos..tokens.count-1 {
        if tokens[pos].type == scope_end {
            return array_view(tokens, start_pos, pos - start_pos);
        }
    }
    log_error("Unexpected end of scope. Expected %", scope_end);
    print_issue(tokens[start_pos].line, tokens[start_pos].character);
    exit(1);
    return tokens;
}

eat_expected :: (tokens: []TOML_Token, pos: *int, expected: Token_Type) {
    if tokens[<<pos].type != expected {
        log_error("Expected %, got %", expected, tokens[<<pos].type);
        print_issue(tokens[<<pos].line, tokens[<<pos].character);
        exit(1);
    }
    <<pos += 1;
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
