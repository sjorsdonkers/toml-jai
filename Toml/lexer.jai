// This lexer does not parse keys or literals, it just determines scopes of chars or tokens.
// NOTE: The keys and literals point into the input data string.
// It is up to the caller to determine when is the best time to put them in a permnent location.

Token :: struct {
    Type :: enum u8 {
        RAW           :: 0;         // str
        QUOTED        :: 1;         // str
        QUOTED_MULTI  :: 2;         // str   // Not using QUOTED as multi-line string cannot be keys
        COMMA         :: #char ","; // -
        DOT           :: #char "."; // -     // Not produced by lexer itself
        ASSIGN        :: #char "="; // -
        SCOPE_BRACKET :: #char "["; // scope
        SCOPE_BRACE   :: #char "{"; // scope
    }
    type: Type;
    union {
        str  : string;  // View into `data`
        scope: []Token; // View into `tokens` starting at the next token
    };
    loc: Location; // TODO Remove, instead always store string to data, in error case it is OK to recompute line and character
}

Location :: struct {
    line, char: s32; // Line and column number, not index
}

Lexer :: struct {
    data: string;            // The original TOML input string
    tokens: [..]Token;       // The lexed tokens to be returned
    pos: s64 = 0;            // Index into data of the current char to be evaluated
    loc: Location = .{1, 1}; // Location of the current char
    scope_stack: [..]int;    // Indices into `tokens` for scopes that have not been closed yet `{` and `[`
}

tokenize :: (data: string) -> tokens: [..]Token { // TODO Change to streaming lexer once all requirements are in
    lexer := Lexer.{data=data};
    lexer.scope_stack.allocator = temp; // Deeply nested scopes are unlikely, so not expecting get large
    array_reserve(*lexer.tokens, data.count / 2); // Rough estimate of token count

    while has_next(lexer) {
        c := peak_char(lexer);
        if c == #char " " || c == #char "\t" {
            eat_char(*lexer);
            continue;
        }

        if c == #char "\n" { eat_newline(*lexer); continue;}
        if has_next(lexer, 2) && peak_slice(lexer, 2) == "\r\n" {
            eat_char(*lexer);
            eat_newline(*lexer);
            continue;
        }

        if c == #char "#" { // NOTE: Also eats \r if any
            while has_next(lexer) && peak_char(lexer) != #char "\n" { eat_char(*lexer); }
            continue;
        }

        // Raw
        is_raw :: (c: u8) -> bool { return is_alnum(c) || c == #char "+" || c == #char "-" || c == #char "." || c == #char ":"; }
        if is_raw(c) {
            start := lexer.pos;
            while has_next(lexer) && is_raw(peak_char(lexer)) { eat_char(*lexer); }
            token := Token.{ type=.RAW, str=slice(lexer.data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - cast(s32) (lexer.pos - start)} };
            array_add(*lexer.tokens, token);
            continue;
        }

        // Literal string
        if c == #char "'" || c == #char "\"" {
            tripple_quote := ifx c == #char "'" then "'''" else "\"\"\"";
            if has_next(lexer, 3) && peak_slice(lexer, 3) == tripple_quote {
                eat_char(*lexer, 3);
                /// Trim newline immediately following ''' if present
                if has_next(lexer) {
                    if c == #char "\n" { eat_newline(*lexer); }
                    if has_next(lexer, 2) && peak_slice(lexer, 2) == "\r\n" {
                        eat_char(*lexer);
                        eat_newline(*lexer);
                    }
                }
                start := lexer.pos;
                while has_next(lexer, 3) && peak_slice(lexer, 3) != tripple_quote {
                    if c == #char "\"" && has_next(lexer, 2) && peak_slice(lexer, 2) == "\\\"" { eat_char(*lexer, 2); continue; }
                    if peak_char(lexer) == #char "\n" { eat_newline(*lexer); }
                    else                              { eat_char(*lexer); }
                }
                if !has_next(lexer) {
                    log_error("Unterminated multi-line string. %:%", lexer.loc.line, lexer.loc.char);
                    exit(1);
                }
                // 1 or 2 quotes at the end are allowed
                if has_next(lexer, 4) && peak_char(lexer, 4) == c { eat_char(*lexer); }
                if has_next(lexer, 4) && peak_char(lexer, 4) == c { eat_char(*lexer); }
                token := Token.{ type=.QUOTED_MULTI, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - cast(s32) (lexer.pos - start)} };
                if c == #char "\"" {
                    // TODO replace token.str by unescaped string
                }
                array_add(*lexer.tokens, token);
                eat_char(*lexer, 3);
                continue;
            }
            // Single line literal string
            eat_char(*lexer);
            start := lexer.pos;
            while has_next(lexer) && peak_char(lexer) != c {
                if c == #char "\"" && has_next(lexer, 2) && peak_slice(lexer, 2) == "\\\"" { eat_char(*lexer, 2); continue; }
                if peak_char(lexer) == #char "\n" {
                    log_error("Newline in string. Use a multi-line string (tripple quote) instead.  %:%", lexer.loc.line, lexer.loc.char);
                    exit(1);
                }
                eat_char(*lexer);
            }
            if !has_next(lexer) {
                log_error("Unterminated string. %:%", lexer.loc.line, lexer.loc.char);
                exit(1);
            }
            token := Token.{ type=.QUOTED, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - cast(s32) (lexer.pos - start)} };
            if c == #char "\"" {
                // TODO replace token.str by unescaped string
            }
            array_add(*lexer.tokens, token);
            eat_char(*lexer);
            continue;
        }

        // Scopes
        if c == #char "{"
        || c == #char "[" {
            scope_index := lexer.tokens.count;
             // .scope is replaced by actual scope on scope closing, scope.count points to the slice token itself for now
            token := Token.{ type=cast(Token.Type) c, scope = lexer.tokens, loc=Location.{lexer.loc.line, lexer.loc.char} };
            array_add(*lexer.tokens, token);
            array_add(*lexer.scope_stack, scope_index);
            eat_char(*lexer);
            continue;
        }
        if c == #char "}"
        || c == #char "]" {
            if lexer.scope_stack.count == 0 {
                log_error("Mismatched braces. No scope opened for: %", c); // TODO more info
                exit(1);
            }
            removed_idx := pop(*lexer.scope_stack);
            if lexer.tokens[removed_idx].type != cast(Token.Type) matching_open(c) {
                log_error("Mismatched scope closure. Scope Opened with: % Attempt to close with: %", lexer.tokens[removed_idx].type, c); // TODO more info
                exit(1);
            }
            scope_count := lexer.tokens.count - lexer.tokens[removed_idx].scope.count - 1;
            lexer.tokens[removed_idx].scope = array_view(lexer.tokens, lexer.tokens[removed_idx].scope.count+1, scope_count);
            eat_char(*lexer);
            continue;
        }

        // Others
        if c == #char ","
        || c == #char "=" {
            token := Token.{ type=cast(Token.Type) c, loc=Location.{lexer.loc.line, lexer.loc.char} };
            array_add(*lexer.tokens, token);
            eat_char(*lexer);
            continue;
        }

        log_error("Invalid character % at %:%", c, lexer.loc.line, lexer.loc.char);
        exit(1);
    }
    return lexer.tokens;
}

#scope_file

has_next :: (lexer: Lexer, count:=1) -> bool {
    return lexer.pos + count -1 < lexer.data.count;
}
peak_char :: (lexer: Lexer, forward:=1) -> u8 {
    return lexer.data[lexer.pos + forward -1];
}
peak_slice :: (lexer: Lexer, count:=1) -> string {
    return slice(lexer.data, lexer.pos, count);
}
eat_char :: (lexer: *Lexer, count:s32=1) {
    lexer.pos += count;
    lexer.loc.char += count;
}
eat_newline :: (lexer: *Lexer) {
    lexer.pos += 1;
    lexer.loc.char = 1;
    lexer.loc.line += 1;
}

matching_open :: (close: u8) -> open: u8 {
    if close == #char "}" { return #char "{"; }
    if close == #char "]" { return #char "["; }
    log_error("No matching open for %", close);
    exit(1);
    return 0;
}

#import "Basic";
