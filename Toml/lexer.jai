Token_Type :: enum u8 {
    RAW           :: 1;         // str
    QUOTED        :: 2;         // str
    COMMA         :: #char ","; // -
    DOT           :: #char "."; // -     // Not produced by lexer itself
    ASSIGN        :: #char "="; // -
    SCOPE_BRACKET :: #char "["; // scope
    SCOPE_BRACE   :: #char "{"; // scope
}

TOML_Token :: struct {
    type: Token_Type;
    union {
        str  :   string;
        scope: []TOML_Token;
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


        // Raw
        is_raw_start :: (c: u8) -> bool { return is_alnum(c) || c == #char "+" || c == #char "-" || c == #char "."; }
        is_raw_char  :: (c: u8) -> bool { return is_alnum(c) || c == #char "+" || c == #char "-" || c == #char "." || c == #char ":"; }
        if is_raw_start(data[pos]) {
            start := pos;
            while pos < data.count && is_raw_char(data[pos]) {
                pos += 1;
                char_number += 1;
            }
            token := TOML_Token.{type=.RAW, str=slice(data, start, pos - start), line=line_number, character=char_number - cast(s32) (pos - start)};
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
            token := TOML_Token.{type=.QUOTED, str=slice(data, start, pos - start), line=line_number, character=char_number - cast(s32) (pos - start)};
            array_add(*tokens, token);
            pos += 1;
            char_number += 1;
            continue;
        }
        if data[pos] == #char "\"" {
            log_error("Basic strings are not supported yet. Use single quotes for literal strings. %:%", line_number, char_number);
            exit(1);
        }

        // Scopes
        if data[pos] == #char "{"
        || data[pos] == #char "[" {
            scope_index := tokens.count;
             // .scope is replaced by actual scope on scope closing, scope.count points to the slice token itself for now
            token := TOML_Token.{type=cast(Token_Type) data[pos], scope = tokens, line=line_number, character=char_number};
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
            scope_count := tokens.count - tokens[removed_idx].scope.count - 1;
            tokens[removed_idx].scope = array_view(tokens, tokens[removed_idx].scope.count+1, scope_count);
            pos += 1;
            char_number += 1;
            continue;
        }

        // Others
        if data[pos] == #char ","
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
