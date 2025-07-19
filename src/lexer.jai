// This lexer does not parse keys or literals, it just determines scopes of chars or tokens.
// NOTE: The keys and literals point into the input data string.

#scope_module

Token :: struct {
    Type :: enum u8 {
        RAW           :: 0;         // str
        LITERAL       :: 1;         // str
        LITERAL_MULTI :: 2;         // str   // Not using LITERAL as multi-line string cannot be keys
        BASIC         :: 3;         // str   // Not using LITERAL as BASIC still needs to be unescaped
        BASIC_MULTI   :: 4;         // str   // Not using BASIC as multi-line string cannot be keys
        COMMA         :: #char ","; // -
        DOT           :: #char "."; // -     // Not produced by lexer itself
        ASSIGN        :: #char "="; // -
        SCOPE_BRACKET :: #char "["; // scope
        SCOPE_BRACE   :: #char "{"; // scope
    }
    type: Type;
    union {
        str  : string;        // View into `data`
        scope: []Token = ---; // View into `tokens` starting at the next token
    };
    loc: Location;
}

Location :: struct {
    line, char: s32; // Line and column number, not index
}

tokenize :: (data: string) -> ok:=false, tokens:[..]Token=[..]Token.{} {
    lexer := Lexer.{data=data}; // Not freeing scope_stack as it will be in a Pool
    array_reserve(*lexer.tokens, data.count / 2); // Rough estimate of token count

    while has_next(lexer) {
        c := peek_char(lexer);
        if c == " " || c == "\t" {
            eat_char(*lexer);
            continue;
        }

        if c == "\n" { eat_newline(*lexer); continue;}
        if has_next(lexer, 2) && peek_slice(lexer, 2) == "\r\n" {
            eat_char(*lexer);
            eat_newline(*lexer);
            continue;
        }

        if c == "#" { // NOTE: Also eats \r if any
            while has_next(lexer) && peek_char(lexer) != "\n" { eat_char(*lexer); }
            continue;
        }

        // Raw
        is_raw :: (c: u8) -> bool { return is_alnum(c) || c == "+" || c == "-" || c == "." || c == ":"; }
        if is_raw(c) {
            start := lexer.pos;
            while has_next(lexer) && is_raw(peek_char(lexer)) { eat_char(*lexer); }
            token := Token.{ type=.RAW, str=slice(lexer.data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - xx (lexer.pos - start)} };
            array_add(*lexer.tokens, token);
            continue;
        }

        // Quoted string
        if c == "'" || c == "\"" {
            tripple_quote := ifx c == "'" then "'''" else "\"\"\"";
            if has_next(lexer, 3) && peek_slice(lexer, 3) == tripple_quote {
                // Multi-line quoted string
                eat_char(*lexer, 3);
                /// Trim newline immediately following ''' if present
                if has_next(lexer) {
                    if peek_char(lexer) == "\n" { eat_newline(*lexer); }
                    if has_next(lexer, 2) && peek_slice(lexer, 2) == "\r\n" {
                        eat_char(*lexer);
                        eat_newline(*lexer);
                    }
                }
                start := lexer.pos;

                // Eat string contents till the end
                while has_next(lexer, 3) && peek_slice(lexer, 3) != tripple_quote {
                    if c == "\"" && has_next(lexer, 2) && peek_slice(lexer, 2) == "\\\"" { eat_char(*lexer, 2); continue; }
                    if peek_char(lexer) == "\n" { eat_newline(*lexer); }
                    else                              { eat_char(*lexer); }
                }
                if !has_next(lexer) { return_with_error_line(lexer.data, lexer.loc, "Unterminated multi-line string."); }
                // 1 or 2 quotes at the end are allowed, like """"abra""""" -> "abra""
                if has_next(lexer, 4) && peek_char(lexer, 4) == c { eat_char(*lexer); }
                if has_next(lexer, 4) && peek_char(lexer, 4) == c { eat_char(*lexer); }

                token_type :Token.Type= ifx c == "\"" then .BASIC_MULTI else .LITERAL_MULTI;
                token := Token.{ type=token_type, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - xx (lexer.pos - start)} };
                array_add(*lexer.tokens, token);
                eat_char(*lexer, 3);
                continue;
            } else {
                // Single-line quoted string
                eat_char(*lexer);
                start := lexer.pos;
                // Eat string contents till the end
                while has_next(lexer) && peek_char(lexer) != c {
                    if c == "\"" && has_next(lexer, 2) {
                        next_two := peek_slice(lexer, 2);
                        if next_two == "\\\""  || next_two == "\\\\" { eat_char(*lexer, 2); continue; }
                    }
                    if peek_char(lexer) == "\n" { return_with_error_line(lexer.data, lexer.loc, "Newline in string. Escape `\\n` or use a multi-line string (tripple quote) instead."); }
                    eat_char(*lexer);
                }
                if !has_next(lexer) { return_with_error_line(lexer.data, lexer.loc, "Unterminated string."); }

                token_type :Token.Type= ifx c == "\"" then .BASIC else .LITERAL;
                token := Token.{ type=token_type, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - xx (lexer.pos - start)} };
                array_add(*lexer.tokens, token);
                eat_char(*lexer);
                continue;
            }
        }

        // Scopes
        if c == "{" || c == "[" {
            scope_index := lexer.tokens.count;
             // .scope is replaced by actual scope on scope closing, scope.count points to the slice token itself for now
            token := Token.{ type=xx c, scope = lexer.tokens, loc=Location.{lexer.loc.line, lexer.loc.char} };
            array_add(*lexer.tokens, token);
            array_add(*lexer.scope_stack, scope_index);
            eat_char(*lexer);
            continue;
        }
        if c == "}" || c == "]" {
            if lexer.scope_stack.count == 0 { return_with_error_line(lexer.data, lexer.loc, "Mismatched braces. No scope opened for: %", to_string(*c, 1)); }

            scope_token := *lexer.tokens[pop(*lexer.scope_stack)];
            if !(scope_token.type == #char "{" && c == "}") && !(scope_token.type == #char "[" && c == "]") {
                return_with_error_line(lexer.data, lexer.loc, "Mismatched scope closure. Scope Opened with: % Attempt to close with: %", to_string(*cast(u8, scope_token.type), 1), to_string(*c,1));
            }

            tokens_in_scope := lexer.tokens.count - scope_token.scope.count - 1;
            scope_token.scope = array_view(lexer.tokens, scope_token.scope.count+1, tokens_in_scope);
            eat_char(*lexer);
            continue;
        }

        // Others
        if c == "," || c == "=" {
            array_add(*lexer.tokens, .{ type=xx c, loc=lexer.loc});
            eat_char(*lexer);
            continue;
        }

        return_with_error_line(lexer.data, lexer.loc, "Invalid character %", to_string(*c, 1));
    }
    return true, lexer.tokens;
}

Lexer :: struct {
    data: string;            // The original TOML input string
    tokens: [..]Token;       // The lexed tokens to be returned
    pos: s64      = 0;       // Index into data of the current char to be evaluated
    loc: Location = .{1, 1}; // Location of the current char
    scope_stack: [..]int;    // Indices into `tokens` for scopes that have not been closed yet `{` and `[`
}
has_next   :: (lexer: Lexer, count:=1) -> bool    { return lexer.pos + count -1 < lexer.data.count; }
peek_char  :: (lexer: Lexer, forward:=1) -> u8    { return lexer.data[lexer.pos + forward -1]; }
peek_slice :: (lexer: Lexer, count:s64) -> string { return slice(lexer.data, lexer.pos, count); }
eat_char :: (lexer: *Lexer, count:s32=1) {
    lexer.pos += count;
    lexer.loc.char += count;
}
eat_newline :: (lexer: *Lexer) {
    lexer.pos += 1;
    lexer.loc.char = 1;
    lexer.loc.line += 1;
}

get_line :: (data: string, line_number: s32) -> line: string, found:bool {
    #import "Text_File_Handler";
    line: string;
    found: bool;
    for 1..line_number { line, found = consume_next_line(*data); }
    return line, found;
}

#scope_export

return_with_error :: (format: string, arguments: .. Any) #expand {
    log_error(format, ..arguments);
    `return;
}

return_with_error_line :: (source: string, loc: Location, format: string, arguments: .. Any) #expand {
    line, found := get_line(source, loc.line);
    if !found {
        log_error("Failed to read line % from file", loc.line);
        `return;
    }
    message := tprint(format, ..arguments);
    log_error("Line % Char %: %", loc.line, loc.char, message);
    log_error(line);

    // print ^^ under the char number
    builder: String_Builder;
    for 1..loc.char-1 { append(*builder, " "); }
    append(*builder, "^");
    log_error(builder_to_string(*builder));

    `return;
}

#scope_file
#import "Basic";
