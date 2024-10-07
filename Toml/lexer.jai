Token_Type :: enum u8 {
    // utf8 controll characters are not allowed in TOML
    KEY     :: 1;
    BOOLEAN :: 2;
    INTEGER :: 3;
    FLOAT   :: 4;
    STRING        :: #char "\"";   // ASCII 34
    COMMA         :: #char ",";    // ASCII 44
    DOT           :: #char ".";    // ASCII 46
    ASSIGN        :: #char "=";    // ASCII 61
    SCOPE_BRACKET :: #char "[";    // ASCII 91  // Stores index to scope array
    SCOPE_BRACE   :: #char "{";    // ASCII 123
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

#import "Basic";
