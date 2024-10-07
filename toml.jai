// Does note support:
// - Multi-line strings
// - String literals
// - Esapeced characters in strings
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
    tokens := lex_toml(contents);

    print_keys :: (keyvals : []KeyValue, indent:="") {
        for keyval: keyvals {
            if keyval.value.type == Value_Type.TABLE { print("% %\n", indent, keyval.key); }
            else {
                if keyval.type == {
                    case .STRING; print("% % = %\n", indent, keyval.key, keyval.string_value);
                    case .INT; print("% % = %\n", indent, keyval.key, keyval.int_value);
                    case .FLOAT; print("% % = %\n", indent, keyval.key, keyval.float_value);
                    case .BOOL; print("% % = %\n", indent, keyval.key, keyval.bool_value);
                    case .ARRAY; print("% % = %\n", indent, keyval.key, keyval.array);
                }
            } // TODO union instead of always string

            if keyval.value.type == Value_Type.TABLE {
                new_indent := tprint("%  ", indent);
                print_keys(keyval.value.table, new_indent);
            }
        }
    }

    root := parse(tokens);
    print("\n\n");
    print_keys(root);
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

// Attop level we can expect (keys, [keys], [[keys]])
parse :: (tokens: []TOML_Token) -> root_table:[..]KeyValue { // Consider just returning a Value
    pos := 0;
    // We use a Root instead of justa an array to make sure overlapping keys are handled in parse_key
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
    return root_table.table;
}

// parse key.key.key.etc =
parse_key :: (parent: *KeyValue, tokens: []TOML_Token) -> root:KeyValue, leaf:*KeyValue { // Root is weird  if parent is set
    print("parse_key\n");
    pos := 0;
    if pos >= tokens.count {
        log_error("Unexpected end of scope while parsing key"); // todo simplify
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
    print("parse_value\n");
    if pos >= tokens.count {
        log_error("Unexpected end of file while parsing value");
        exit(1);
    }

    token := tokens[pos];
    if token.type == Token_Type.SCOPE_BRACE {
        table := parse_inline_table(current_key, token.scope);
        pos += token.scope.count + 1;
        return table, pos;
    } else if token.type == Token_Type.SCOPE_BRACKET {
        array := parse_array(token.scope);
        pos += token.scope.count + 1;
        return array, pos;
    } else {
        literal := parse_literal(token);
        pos += 1;
        return literal, pos;
    }
}

parse_inline_table :: (current_key: *KeyValue, tokens: []TOML_Token) -> table:Value {
    print("parse_inline_table\n");
    pos := 0;
    table_root := KeyValue.{"*TABLE_ROOT*", Value.{type=.TABLE}}; // TODO root name should be something not possible in TOML
    if current_key == null { current_key = *table_root; }
    while pos < tokens.count {
        // Inline tables are not allowed to have trailing commas
        if tokens[pos].type == Token_Type.COMMA { pos += 1; }

        keys_scope := make_scope_until(tokens, pos, Token_Type.ASSIGN);
        _, leaf_key := parse_key(current_key, keys_scope);
        pos += keys_scope.count + 1;
        leaf_key.value, pos = parse_value(leaf_key, tokens, pos);
    }
    return current_key.value;
}

parse_array :: (tokens: []TOML_Token) -> array:Value { // TODO parent
    print("parse_array\n");
    pos := 0;
    values : [..]Value;
    while pos < tokens.count {
        value :Value;
        value, pos = parse_value(null, tokens, pos); // Does this work?
        array_add(*values, value);
        if pos == tokens.count { break; }
        eat_expected(tokens, *pos, Token_Type.COMMA);
    }
    return Value.{type=.ARRAY, array=values};
}

parse_literal :: (token: TOML_Token) -> Value {
    print("parse literal\n");
    if token.type == Token_Type.BOOLEAN {
        return Value.{type=.BOOL, bool_value=token.bool_value};
    } else if token.type == Token_Type.INTEGER {
        return Value.{type=.INT, int_value=token.int_value};
    } else if token.type == Token_Type.FLOAT {
        return Value.{type=.FLOAT, float_value=token.float_value};
    } else if token.type == Token_Type.STRING {
        return Value.{type=.STRING, string_value=token.slice}; // TODO
    } else {
        log_error("Unexpected token %, expected a value", token.type);
        print_issue(token.first_line, token.first_char);
        exit(1);
        return Value.{};
    }
}

make_scope_until :: (tokens: []TOML_Token, start_pos: int, scope_end: $Token_Type) -> []TOML_Token { // TODO what does the $ do here?
    for pos: start_pos..tokens.count-1 {
        if tokens[pos].type == scope_end {
            return array_view(tokens, start_pos, pos - start_pos);
        }
    }
    log_error("Unexpected end of file. Expected %", scope_end);
    exit(1);
    return tokens;
}

eat_expected :: (tokens: []TOML_Token, pos: *int, expected: $Token_Type) {
    if tokens[<<pos].type != expected {
        log_error("Expected %, got %", expected, tokens[<<pos].type);
        print_issue(tokens[<<pos].first_line, tokens[<<pos].first_char);
        exit(1);
    }
    <<pos += 1;
}

// //alternative data structures, but tables in arrays are akward
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



Module_Info :: struct {
    alias: string;
    git: string;
    branch: string;
    commit: string;
    path: string;
}

Token_Type :: enum u8 {
    // utf8 controll characters are not allowed in TOML
    KEY     :: 1;
    BOOLEAN :: 2;
    INTEGER :: 3;
    FLOAT   :: 4;
    STRING  :: #char "\""; // ASCII 34
    // COMMENT :: #char "#"; // ASCII 35
    // RAW_STRING :: #char "'"; // ASCII 39
    // OFFSET_DATE_TIME :: 5; // Do we care?
    // LOCAL_DATE_TIME  :: 6;
    // LOCAL_DATE       :: 7;
    // LOCAL_TIME       :: 8;

    // TAB           :: #char "\t";   // ASCII 9
    // NEWLINE       :: #char "\n";   // ASCII 10
    // CR            :: #char "\r";   // ASCII 13
    // SPACE         :: #char " ";    // ASCII 32
    COMMA         :: #char ",";    // ASCII 44
    DOT           :: #char ".";    // ASCII 46
    ASSIGN        :: #char "=";    // ASCII 61
    SCOPE_BRACKET  :: #char "[";    // ASCII 91 // Stores index to scope array
    // RIGHT_BRACKET :: #char "]";    // ASCII 93
    SCOPE_BRACE    :: #char "{";    // ASCII 123
    // RIGHT_BRACE   :: #char "}";    // ASCII 125
}

Quote :: enum u8 {
    NONE;
    SINGLE;
    TRIPPLE;
}

TOML_Token :: struct {
    type: Token_Type;
    slice: string;
    union {
        bool_value : bool;
        int_value  : s64;
        float_value: float64;
        // string_value: string; // TODO
        scope: []TOML_Token;
    };
    first_line, first_char: s32;
    last_line, last_char: s32 = -1;
    // quoting: Quote = Quote.NONE;
}

lex_toml :: (data: string) -> tokens: [..]TOML_Token {
    pos := 0;
    tokens : [..]TOML_Token;
    line_number: s32 = 1;
    char_number: s32 = 1;

    scope_stack: [..]int; // Indexes into tokens

    while pos < data.count {
        if is_whitespace(data[pos]) {
            pos += 1;
            char_number += 1;
            continue;
        }

        if is_newline(data[pos]) {
            pos += 1;
            char_number = 1;
            line_number += 1;
            continue;
        }

        if data[pos] == #char "#" {
            start := pos;
            while pos < data.count && !is_newline(data[pos]) {
                pos += 1;
                char_number += 1;
            }
            continue;
        }

        // Check is boolean true and false
        if pos + 4 < data.count {
            next4 := slice(data, pos, 4);
            if next4 == "true" {
                token := TOML_Token.{type=.BOOLEAN, slice=next4, bool_value = true, first_line=line_number, first_char=char_number, last_line=line_number, last_char=char_number + 3};
                array_add(*tokens, token);
                pos += 4;
                char_number += 4;
                continue;
            }
            if pos + 5 < data.count {
                next5 := slice(data, pos, 5);
                if next5 == "false" {
                    token := TOML_Token.{type=.BOOLEAN, slice=next5, bool_value = false, first_line=line_number, first_char=char_number, last_line=line_number, last_char=char_number + 4};
                    array_add(*tokens, token);
                    pos += 5;
                    char_number += 5;
                    continue;
                }
            }
        }

        // Key
        if is_alpha(data[pos]) || data[pos] == #char "_" { // No quotes, No `-`, no numbers
            start := pos;
            while pos < data.count && (is_alnum(data[pos])) {
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.KEY, slice=slice(data, start, pos - start), first_line=line_number, first_char=char_number - cast(s32) (pos - start), last_line=line_number, last_char=char_number - 1};
            array_add(*tokens, token);
            continue;
        }

        // String
        if data[pos] == #char "\"" { // No multi-line yet / No string literals
            pos += 1;
            char_number += 1;
            start := pos;
            while pos < data.count && (data[pos] != #char "\"" || data[pos-1] == #char "\\") {
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.STRING, slice=slice(data, start, pos - start), first_line=line_number, first_char=char_number - cast(s32) (pos - start), last_line=line_number, last_char=char_number - 1};
            array_add(*tokens, token);
            pos += 1;
            char_number += 1;
            continue;
        }

        // Integer
        if is_digit(data[pos]) || data[pos] == #char "-" || data[pos] == #char "+" { // no u64, No floats, no hex, no octal, no binary, no scientific
            start := pos;
            value : s64 = 0;
            while pos < data.count && (is_digit(data[pos])) {
                value = value * 10 + cast(s64) (data[pos] - #char "0");
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.INTEGER, slice=slice(data, start, pos - start), int_value = value, first_line=line_number, first_char=char_number - cast(s32) (pos - start), last_line=line_number, last_char=char_number - 1};
            array_add(*tokens, token);
            continue;
        }

        // Scopes
        if data[pos] == #char "{"
        || data[pos] == #char "[" {
            scope_index := tokens.count;
            token := TOML_Token.{
                type=cast(Token_Type) data[pos],
                slice=slice(data, pos, 1),   // To be updated on scope close
                int_value = scope_index + 1, // To be replaced by scope on scope close
                first_line=line_number,
                first_char=char_number,
            };
            array_add(*tokens, token);
            array_add(*scope_stack, scope_index);
            pos += 1;
            char_number += 1;
            continue;
        }
        if data[pos] == #char "}"
        || data[pos] == #char "]" {
            if scope_stack.count == 0 {
                log_error("Mismatched braces. No scope opened for: %", data[pos]); // TODO more info
                exit(1);
            }
            removed_idx := pop(*scope_stack);
            if tokens[removed_idx].type != cast(Token_Type) matching_open(data[pos]) {
                log_error("Mismatched scope closure. Scope Opened with: % Attempt to close with: %", tokens[removed_idx].type, data[pos]); // TODO more info
                exit(1);
            }
            char_count := pos - (tokens[removed_idx].slice.data - data.data) + 1;
            tokens[removed_idx].slice.count = char_count;
            scope_count := tokens.count - tokens[removed_idx].int_value; // -1
            tokens[removed_idx].scope = array_view(tokens, tokens[removed_idx].int_value, scope_count);
            pos += 1;
            char_number += 1;
            continue;
        }

        // Others
        if data[pos] == #char ","
        || data[pos] == #char "."
        || data[pos] == #char "=" {
            token := TOML_Token.{type=cast(Token_Type) data[pos], slice=slice(data, pos, 1), first_line=line_number, first_char=char_number};
            array_add(*tokens, token);
            pos += 1;
            char_number += 1;
            continue;
        }

        log_error("Invalid character % at %:%", data[pos], line_number, char_number);
        exit(1);
    }
    return tokens;
}

is_whitespace :: (c: u8) -> bool {
    return c == #char " " || c == #char "\t" || c == #char "\r";
}

is_newline :: (c: u8) -> bool {
    return c == #char "\n";
}

matching_open :: (close: u8) -> open: u8 {
    if close == #char "}" {
        return #char "{";
    }
    if close == #char "]" {
        return #char "[";
    }
    log_error("No matching open for %", close);
    exit(1);
    return 0;
}

using Basic :: #import "Basic";
#poke_name Basic operator==;
#import "File";
#import "String";
