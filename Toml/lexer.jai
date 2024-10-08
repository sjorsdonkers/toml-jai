Token_Type :: enum u8 {
    KEY           :: 1;         // string_value
    BOOLEAN       :: 2;         // bool_value
    INTEGER       :: 3;         // int_value
    STRING        :: #char "'"; // string_value
    COMMA         :: #char ","; // -
    DOT           :: #char "."; // -
    ASSIGN        :: #char "="; // -
    SCOPE_BRACKET :: #char "["; // scope
    SCOPE_BRACE   :: #char "{"; // scope
}

TOML_Token :: struct {
    type: Token_Type;
    union {
        bool_value  : bool;
        int_value   : s64;
        string_value: string;
        scope       : []TOML_Token;
    };
    line, character: s32;
}

tokenize :: (data: string) -> tokens: [..]TOML_Token {
    pos := 0;
    tokens : [..]TOML_Token;
    array_reserve(*tokens, data.count / 2); // Rough estimate of token count
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
            if slice(data, pos, 4) == "true" {
                token := TOML_Token.{type=.BOOLEAN, bool_value = true, line=line_number, character=char_number};
                array_add(*tokens, token);
                pos += 4;
                char_number += 4;
                continue;
            }
            if pos + 5 < data.count
            && slice(data, pos, 5) == "false" {
                token := TOML_Token.{type=.BOOLEAN, bool_value = false, line=line_number, character=char_number};
                array_add(*tokens, token);
                pos += 5;
                char_number += 5;
                continue;
            }
        }

        // Key
        if is_alpha(data[pos]) || data[pos] == #char "_" { // No quotes, No `-`, no starting numbers
            start := pos;
            while pos < data.count && (is_alnum(data[pos])) {
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.KEY, string_value=slice(data, start, pos - start), line=line_number, character=char_number - cast(s32) (pos - start)};
            array_add(*tokens, token);
            continue;
        }

        // Literal string
        if data[pos] == #char "'" { // No multi-line yet / No basic string
            if pos + 3 < data.count && slice(data, pos, 3) == "'''" {
                log_error("Multi-line literal strings are not supported yet. Use single line strings only. %:%", line_number, char_number);
                exit(1);
            }
            pos += 1;
            char_number += 1;
            start := pos;
            while pos < data.count && (data[pos] != #char "'") {
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.STRING, string_value=slice(data, start, pos - start), line=line_number, character=char_number - cast(s32) (pos - start)};
            array_add(*tokens, token);
            pos += 1;
            char_number += 1;
            continue;
        }
        if data[pos] == #char "\"" {
            log_error("Basic strings are not supported yet. Use single quotes for literal strings. %:%", line_number, char_number);
            exit(1);
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
            token := TOML_Token.{type=.INTEGER, int_value = value, line=line_number, character=char_number - cast(s32) (pos - start)};
            array_add(*tokens, token);
            continue;
        }

        // Scopes
        if data[pos] == #char "{"
        || data[pos] == #char "[" {
            scope_index := tokens.count;
             // int_value is replaced by scope on scope closing, it does not include the scope tokens itself
            token := TOML_Token.{type=cast(Token_Type) data[pos], int_value = scope_index + 1, line=line_number, character=char_number};
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
            scope_count := tokens.count - tokens[removed_idx].int_value;
            tokens[removed_idx].scope = array_view(tokens, tokens[removed_idx].int_value, scope_count);
            pos += 1;
            char_number += 1;
            continue;
        }

        // Others
        if data[pos] == #char ","
        || data[pos] == #char "."
        || data[pos] == #char "=" {
            token := TOML_Token.{type=cast(Token_Type) data[pos], line=line_number, character=char_number};
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
