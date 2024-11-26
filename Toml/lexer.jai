// This lexer does not parse keys or literals, it just determines scopes of chars or tokens.
// NOTE: The keys and literals point into the input data string.
// It is up to the caller to determine when is the best time to put them in a permanent location.

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

        // Quoted string
        if c == #char "'" || c == #char "\"" {
            tripple_quote := ifx c == #char "'" then "'''" else "\"\"\"";
            if has_next(lexer, 3) && peak_slice(lexer, 3) == tripple_quote {
                // Multi-line quoted string
                eat_char(*lexer, 3);
                /// Trim newline immediately following ''' if present
                if has_next(lexer) {
                    if peak_char(lexer) == #char "\n" { eat_newline(*lexer); }
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
                if !has_next(lexer) { exit_with_error_line(lexer.data, lexer.loc, "Unterminated multi-line string."); }
                // 1 or 2 quotes at the end are allowed
                if has_next(lexer, 4) && peak_char(lexer, 4) == c { eat_char(*lexer); }
                if has_next(lexer, 4) && peak_char(lexer, 4) == c { eat_char(*lexer); }

                token := Token.{ type=.QUOTED_MULTI, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - cast(s32) (lexer.pos - start)} };
                if c == #char "\"" { token.str = unescape(*lexer, token.str); }
                array_add(*lexer.tokens, token);
                eat_char(*lexer, 3);
                continue;
            }
            // Single-line quoted string
            eat_char(*lexer);
            start := lexer.pos;
            while has_next(lexer) && peak_char(lexer) != c {
                if c == #char "\"" && has_next(lexer, 2) && peak_slice(lexer, 2) == "\\\"" { eat_char(*lexer, 2); continue; }
                if peak_char(lexer) == #char "\n" { exit_with_error_line(lexer.data, lexer.loc, "Newline in string. Use a multi-line string (tripple quote) instead."); }
                eat_char(*lexer);
            }
            if !has_next(lexer) { exit_with_error_line(lexer.data, lexer.loc, "Unterminated string."); }

            token := Token.{ type=.QUOTED, str=slice(data, start, lexer.pos - start), loc=Location.{lexer.loc.line, lexer.loc.char - cast(s32) (lexer.pos - start)} };
            if c == #char "\"" { token.str = unescape(*lexer, token.str); }
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
            if lexer.scope_stack.count == 0 { exit_with_error_line(lexer.data, lexer.loc, "Mismatched braces. No scope opened for: %", to_string(*c, 1)); }

            removed_idx := pop(*lexer.scope_stack);
            if lexer.tokens[removed_idx].type != cast(Token.Type) matching_open(c) {
                exit_with_error_line(lexer.data, lexer.loc, "Mismatched scope closure. Scope Opened with: % Attempt to close with: %", to_string(*cast(u8)lexer.tokens[removed_idx].type, 1), to_string(*c,1));
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

        exit_with_error_line(lexer.data, lexer.loc, "Invalid character %", to_string(*c, 1));
    }
    return lexer.tokens;
}

#scope_file

Lexer :: struct {
    data: string;            // The original TOML input string
    tokens: [..]Token;       // The lexed tokens to be returned
    pos: s64 = 0;            // Index into data of the current char to be evaluated
    loc: Location = .{1, 1}; // Location of the current char
    scope_stack: [..]int;    // Indices into `tokens` for scopes that have not been closed yet `{` and `[`
    builder: String_Builder;
}
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
    exit_with_error("No matching open for %", to_string(*close, 1));
    return 0;
}

unescape :: (lexer: *Lexer, basic: string) -> string { // TODO change builder to lexer to have access to loc
    // TODO if not contains "//" return basic;
    pos := 0;
    while true {
        if pos >= basic.count { break; }
        if basic[pos] == #char "\\" {
            if pos + 1 >= basic.count {exit_with_error_line(lexer.data, lexer.loc, "Unterminated escape sequence"); }

            if basic[pos + 1] == {
            case #char "b";  append(*lexer.builder, #char "\x08"); pos += 2;
            case #char "t";  append(*lexer.builder, #char "\t"); pos += 2;
            case #char "n";  append(*lexer.builder, #char "\n"); pos += 2;
            case #char "f";  append(*lexer.builder, #char "\x0c"); pos += 2;
            case #char "r";  append(*lexer.builder, #char "\r"); pos += 2;
            case #char "\""; append(*lexer.builder, #char "\""); pos += 2;
            case #char "\\"; append(*lexer.builder, #char "\\"); pos += 2;
            case #char "\r"; #through; // TOD space and tab
            case #char "\n";
                pos += 2;
                // log("HERE: %", to_string(*basic[pos], 1));
                while (pos < basic.count) && (basic[pos] == #char " "
                                            || basic[pos] == #char "\t"
                                            || basic[pos] == #char "\r"
                                            || basic[pos] == #char "\n") {
                    // log("HERE2: %", to_string(*basic[pos], 1));
                    pos += 1;
                }
            case #char "u"; #through;
            case #char "U";
                num_digits: s32 = xx ifx basic[pos + 1] == #char "u" then 4 else 8;
                if num_digits + 2 >= basic.count {exit_with_error_line(lexer.data, lexer.loc, "Expected % characters in the unicode escape sequence", num_digits); }

                unicode_hex_str := slice(basic, pos+2, num_digits);
                hex_value, success, remainder := string_to_int(unicode_hex_str, 16, u32);
                if !success || remainder.count != 0 {
                    current_loc := lexer.loc;
                    current_loc.char += xx (pos - basic.count);
                    exit_with_error_line(lexer.data, current_loc, "not unicode");
                }

                buf: [4]u8;
                tmp: string;
                tmp.data = buf.data;
                character_utf32_to_utf8(hex_value, *tmp);

                append(*lexer.builder, tmp);
                pos += num_digits + 2;
            case;
                current_loc := lexer.loc;
                current_loc.char += xx (pos - basic.count);
                exit_with_error_line(lexer.data, current_loc, "Invalid escape sequence.");
            }
        } else {
            // log("Char: %", to_string(*basic[pos], 1));
            append(*lexer.builder, basic[pos]);
            pos += 1;
        }
    }
    return builder_to_string(*lexer.builder);
}

get_line :: (data: string, line_number: s32) -> line: string, found:bool {
    #import "Text_File_Handler";
    line: string;
    found: bool;
    for 1..line_number { line, found = consume_next_line(*data); }
    return line, found;
}

#scope_module

exit_with_error :: (format: string, arguments: .. Any) {
    log_error(format, ..arguments);
    exit(1);
}
exit_with_error_line :: (source: string, loc: Location, format: string, arguments: .. Any) {
    line, found := get_line(source, loc.line);
    if !found {
        log_error("Failed to read line % from file", loc.line);
        exit(1);
    }
    message := tprint(format, ..arguments);
    log_error("Line % Char %: %", loc.line, loc.char, message);
    log_error(line);

    // print ^^ under the char number
    builder: String_Builder;
    for 1..loc.char-1 { append(*builder, #char " "); }
    append(*builder, #char "^");
    log_error(builder_to_string(*builder));

    exit(1);
}

#import "Basic";
#import "Unicode";
