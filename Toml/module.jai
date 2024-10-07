// Does note support:
// - Multi-line strings
// - String literals
// - Escaped characters in strings
// - Float, Hex, octal, binary, scientific notation, +-ints
// - Date / Time
// - Arrays of tables
// - Proper toml validation like endlines in an inline table

contents : string; // TODO
print_issue:: (line_number: s32, char_number: s32) {
    #import "Text_File_Handler";
    success, lines := file_to_array(filename="toml.toml", do_trim=false, skip_blank_lines=false, use_data_from_memory=true, data_from_memory=contents);
    if !success {
        log_error("Failed to read file: toml.toml");
        exit(1);
    }
    print("Line % Char %:\n", line_number, char_number);
    print("%\n", lines[line_number - 1]);
    // print ^^ under the char number

    builder: String_Builder;
    for 1..char_number-1 {
        append(*builder, #char " ");
    }
    append(*builder, #char "^"); // Just 1 for now
    pointing_string := builder_to_string(*builder);
    print(pointing_string);
}

main :: () {
    contents = read_entire_file("toml.toml");
    tokens  := lex_toml(contents);
    root    := parse(tokens);
    print_value(root);
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
operator == :: inline (a: KeyValue, b: KeyValue) -> bool {
    // Not a full comparison, just used for array_add_if_unique
    // Consider poking it only where needed
    return a.key == b.key;
}

// At top level we can expect (keys, [keys], [[keys]])
parse :: (tokens: []TOML_Token) -> root_table:Value {
    pos := 0;
    // We use a Root instead of just an array to make sure overlapping keys are handled in parse_key
    root_table := KeyValue.{"*ROOT*", Value.{type=.TABLE}}; // TODO root name should be something not possible in TOML
    current_table := *root_table;
    while pos < tokens.count {
        if tokens[pos].type == Token_Type.SCOPE_BRACKET {
            if pos + 1 < tokens.count && tokens[pos+1].type == Token_Type.SCOPE_BRACKET{
                // TODO handle array of tables
                log_error("Arrays of tables are not supported");
                exit(1);
            }
            _, current_table = parse_key(*root_table, tokens[pos].scope);
            pos += tokens[pos].scope.count + 1;
        } else { // Parse key value pair
            keys_scope := make_scope_until(tokens, pos, Token_Type.ASSIGN);
            _, leaf_key := parse_key(current_table, keys_scope);
            pos += keys_scope.count + 1;
            leaf_key.value, pos = parse_value(leaf_key, tokens, pos);
        }
    }
    return root_table.value;
}

// parse key.key.key.etc =
parse_key :: (parent: *KeyValue, tokens: []TOML_Token) -> root:KeyValue, leaf:*KeyValue { // Root is weird  if parent is set
    pos := 0;
    if pos >= tokens.count {
        log_error("Unexpected end of scope while parsing key"); // todo simplify
        exit(1);
    }
    if tokens[pos].type != Token_Type.KEY {
        log_error("Expected key, got % - %\n", tokens[pos].type, tokens[pos].slice);
        print_issue(tokens[pos].first_line, tokens[pos].first_char);
        exit(1);
    }
    local_root : KeyValue;
    local_root.key = tokens[pos].slice;
    local_root.value = Value.{type=.TABLE};
    pos += 1;

    current_table := *local_root;
    if parent != null {
        if parent.type != Value_Type.TABLE {
            log_error("Cannot use key as table as it already has a value: %", parent.type);
            exit(1);
        }
        _, index := array_add_if_unique(*parent.table, local_root);
        current_table = *parent.table[index];
    }

    while pos < tokens.count {
        eat_expected(tokens, *pos, Token_Type.DOT);
        if pos == tokens.count {
            log_error("Key is not allowed to end with a dot");
            print_issue(tokens[pos-1].first_line, tokens[pos-1].first_char);
            exit(1);
        }
        if tokens[pos].type != Token_Type.KEY {
            log_error("Expected key, got % - %\n", tokens[pos].type, tokens[pos].slice);
            print_issue(tokens[pos].first_line, tokens[pos].first_char);
            exit(1);
        }
        if current_table.type != Value_Type.TABLE {
            log_error("Cannot use key as table it already has a value: %", current_table.type);
            exit(1);
        }
        _, index := array_add_if_unique(*current_table.table, KeyValue.{tokens[pos].slice, Value.{type=.TABLE}});
        current_table = *current_table.table[index];
        pos += 1;
    }
    return local_root, current_table;
}

parse_value :: (current_key: *KeyValue, tokens: []TOML_Token, pos: s64) -> value:Value, pos:s64 { // TODO only assign value if key is empty table
    if pos >= tokens.count {
        log_error("Unexpected end of file while parsing value");
        exit(1);
    }

    token := tokens[pos];
    if token.type == {
    case .SCOPE_BRACE;
        table := parse_inline_table(current_key, token.scope);
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

parse_inline_table :: (current_key: *KeyValue, tokens: []TOML_Token) -> table:Value { // TODO current_key does not need to be a pointer
    // An inline table is either the right-hand side of an assignment to a key
    // or a value in an array. In case of the former it is important that we continue building
    // on the current key as a.b = {c.d = 1} is the same as in a.b.c.d = 1
    pos := 0;
    table_root := KeyValue.{"*TABLE_ROOT*", Value.{type=.TABLE}}; // TODO root name should be something not possible in TOML
    if current_key == null { current_key = *table_root; }
    while pos < tokens.count {
        keys_scope := make_scope_until(tokens, pos, Token_Type.ASSIGN);
        _, leaf_key := parse_key(current_key, keys_scope);
        pos += keys_scope.count + 1;
        leaf_key.value, pos = parse_value(leaf_key, tokens, pos);

        // Inline tables are not allowed to have trailing commas
        if pos+1 < tokens.count { eat_expected(tokens, *pos, Token_Type.COMMA); } // TODO improve error message
    }
    return current_key.value;
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
    case .FLOAT;   return Value.{type=.FLOAT, float_value=token.float_value};
    case .STRING;  return Value.{type=.STRING, string_value=token.slice}; // TODO
    case;
        log_error("Unexpected token %, expected a value", token.type);
        print_issue(token.first_line, token.first_char);
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
    print_issue(tokens[start_pos].first_line, tokens[start_pos].first_char);
    exit(1);
    return tokens;
}

eat_expected :: (tokens: []TOML_Token, pos: *int, expected: Token_Type) {
    if tokens[<<pos].type != expected {
        log_error("Expected %, got %", expected, tokens[<<pos].type);
        print_issue(tokens[<<pos].first_line, tokens[<<pos].first_char);
        exit(1);
    }
    <<pos += 1;
}

// //alternative data structures, but tables in arrays are awkward
// Value :: struct {
//     type: Value_Type;
//     union {
//         bool_value : bool;
//         int_value  : s64;
//         float_value: float64;
//         string_value: string;
//         // date / time
//         array_value: [..]int;
//     };
// }
// TOML_data :: struct {
//     values: [..]Value;
//     keys: [..][..]string;
//     arrays: [..]struct { start: int; end: int; };
// }

// Module_Info :: struct {
//     alias: string;
//     git: string;
//     branch: string;
//     commit: string;
//     path: string;
// }

#scope_file

print_value :: (value : Value, indent:="") {
    if value.type == {
    case .STRING; print("%\n", value.string_value);
    case .INT; print("%\n", value.int_value);
    case .FLOAT; print("%\n", value.float_value);
    case .BOOL; print("%\n", value.bool_value);
    case .ARRAY;
        print("[\n");
        new_indent := tprint("%  ", indent);
        for val: value.array {
            if val.type == .TABLE {
                print_value(val, new_indent);
            }
            else {
                print("%", new_indent);
                print_value(val, new_indent);
            }
        }
        print("%]\n", indent);
    case .TABLE;
        new_indent := tprint("%  ", indent);
        for keyval: value.table {
            print("%0%", indent, keyval.key);
            if keyval.type == .TABLE {
                print("\n");
                print_value(keyval.value, new_indent);
            }
            else {
                print(" = ");
                print_value(keyval.value, indent);
            }
        }
    }
}

#load "lexer.jai";
using Basic :: #import "Basic";
#poke_name Basic operator==;
#import "File";
#import "String";
