main :: () {
    push_allocator(temp);

    json_data := stdinput();
    parser := JSON_Parser.{data = json_data};
    ok, toml_value := parse_json_to_toml(*parser);
    if !ok {
        print("Failed to parse JSON data\n", to_standard_error=true);
        exit(1);
    }

    builder: String_Builder;
    ok = Toml.serialize_to_builder(*builder, toml_value,, toml=.{default_format_float=.{mode=.SCIENTIFIC, trailing_width=15}});
    if !ok {
        print("Failed to serialize TOML\n", to_standard_error=true);
        exit(1);
    }
    write_builder(*builder, false);
}

JSON_Parser :: struct {
    data: string;
    pos: int = 0;
}

parse_json_to_toml :: (parser: *JSON_Parser) -> ok:=false, value:=Toml.Value.{} {
    eat_whitespace(parser);
    if parser.pos >= parser.data.count return;

    char := parser.data[parser.pos];
    if char == {
    case #char "{";
        parser.pos += 1;
        ok, value := parse_object_to_toml(parser);
        return ok, value;
    case #char "[";
        parser.pos += 1;
        ok, value := parse_array_to_toml(parser);
        return ok, value;
    case #char "\"";
        ok, str := parse_string(parser);  if !ok return;
        return true, Toml.Value.{type = .STRING, string_value = str};
    case; return;
    }
}

parse_object_to_toml :: (parser: *JSON_Parser) -> ok:=false, value:=Toml.Value.{} {
    table: [..] Toml.KeyValue;
    while true {
        // Check for end of object
        eat_whitespace(parser);
        if parser.pos < parser.data.count && parser.data[parser.pos] == #char "}" {
            parser.pos += 1;
            break;
        }
        // Parse key
        key_ok, key := parse_string(parser);
        if !key_ok return;

        eat_whitespace(parser);
        if parser.pos >= parser.data.count || parser.data[parser.pos] != #char ":" return;
        parser.pos += 1;

        // Parse value
        eat_whitespace(parser);
        value_ok, value := parse_json_to_toml(parser);
        if !value_ok return;
        array_add(*table, .{key = key, value = value});

        eat_whitespace(parser);
        if parser.pos >= parser.data.count return;
        if parser.data[parser.pos] == #char "," {
            parser.pos += 1;
        }
    }

    // Check if this is a typed value (exactly 2 keys: "type" and "value" with string values)
    if table.count == 2 && table[0].key == "type" && table[1].key == "value" &&
       table[0].value.type == .STRING && table[1].value.type == .STRING {
        ok, typed_value := parse_typed_value(table[0].value.string_value, table[1].value.string_value);
        if ok return true, typed_value;
    }
    return true, Toml.Value.{type = .TABLE, table = table};
}

parse_array_to_toml :: (parser: *JSON_Parser) -> ok:=false, value:=Toml.Value.{} {
    values: [..] Toml.Value;
    while true {
        eat_whitespace(parser);
        if parser.pos < parser.data.count && parser.data[parser.pos] == #char "]" {
            parser.pos += 1;
            break;
        }
        value_ok, value := parse_json_to_toml(parser);
        if !value_ok return;
        array_add(*values, value);

        eat_whitespace(parser);
        if parser.pos >= parser.data.count return;
        if parser.data[parser.pos] == #char "," {
            parser.pos += 1;
        }
    }
    return true, Toml.Value.{type = .ARRAY, array = values};
}

parse_string :: (parser: *JSON_Parser) -> ok:=false, str:="" {
    if parser.pos >= parser.data.count || parser.data[parser.pos] != #char "\"" return;
    parser.pos += 1; // Skip opening quote

    start := parser.pos;
    builder: String_Builder;

    while parser.pos < parser.data.count {
        char := parser.data[parser.pos];

        if char == #char "\"" {
            parser.pos += 1; // Skip closing quote
            return true, builder_to_string(*builder);
        } else if char == #char "\\" {
            parser.pos += 1;
            if parser.pos >= parser.data.count return;

            escape_char := parser.data[parser.pos];
            if escape_char == {
            case #char "\""; append(*builder, "\"");
            case #char "\\"; append(*builder, "\\");
            case #char "/";  append(*builder, "/");
            case #char "b";  append(*builder, "\x08");
            case #char "f";  append(*builder, "\x0c");
            case #char "n";  append(*builder, "\n");
            case #char "r";  append(*builder, "\r");
            case #char "t";  append(*builder, "\t");
            case #char "u";  // Unicode escape sequence \uXXXX
                if parser.pos + 4 >= parser.data.count return;

                hex_str := slice(parser.data, parser.pos + 1, 4);
                hex_value, hex_ok := string_to_int(hex_str, 16, u16);  if !hex_ok return;
                buf: [4]u8;
                tmp := string.{4, buf.data};
                character_utf32_to_utf8(hex_value, *tmp);
                append(*builder, tmp);

                parser.pos += 4;
            case; return;
            }
            parser.pos += 1;
        } else {
            append(*builder, char);
            parser.pos += 1;
        }
    }
    return; // Unterminated string
}

eat_whitespace :: (parser: *JSON_Parser) {
    for char: slice(parser.data, parser.pos, parser.data.count - parser.pos) {
        if !(char == #char " " || char == #char "\t" || char == #char "\n" || char == #char "\r") break;
        parser.pos += 1;
    }
}

parse_typed_value :: (type_str: string, value_str: string) -> ok:=false, value:=Toml.Value.{} {
    if type_str == {
    case "string";  return true, Toml.Value.{type = .STRING, string_value = value_str};
    case "integer";
        int_val, ok := string_to_int(value_str);        if !ok return;
        return true, Toml.Value.{type = .INT, int_value = int_val};
    case "float";
        if value_str ==  {
        case "inf";  return true, Toml.Value.{type = .FLOAT, float_value =  FLOAT64_INFINITY};
        case "-inf"; return true, Toml.Value.{type = .FLOAT, float_value = -FLOAT64_INFINITY};
        case "nan";  return true, Toml.Value.{type = .FLOAT, float_value =  FLOAT64_NAN};
        }
        float_val, ok := string_to_float64(value_str);  if !ok return;
        return true, Toml.Value.{type = .FLOAT, float_value = float_val};
    case "bool";
        if value_str == {
        case "true";  return true, Toml.Value.{type = .BOOL, bool_value = true};
        case "false"; return true, Toml.Value.{type = .BOOL, bool_value = false};
        case;         return;
        }
    case "datetime";       #through;
    case "datetime-local"; #through;
    case "date-local";     #through;
    case "time-local";
        ok, chrono := parse_datetime(value_str); if !ok return;
        return true, .{type=.DATETIME, datetime=chrono};
    }
    return;
}

stdinput :: () -> string {
    buffer: [4096] u8;
    input: string;
    input.data = buffer.data;

    while true {
        // @Incomplete: Jai doesn't have an abstraction for reading from stdin yet...
        #if OS == .WINDOWS {
            handle := GetStdHandle(STD_INPUT_HANDLE);
            bytes_read: u32;
            success := ReadFile(handle, buffer.data + input.count, cast(u32) (buffer.count - input.count), *bytes_read, null);
        } else {
            success := true;
            bytes_read := read(STDIN_FILENO, buffer.data + input.count, cast(u64) (buffer.count - input.count));
            if bytes_read < 0 { log_error("Couldn't read from stdin"); exit(1); }
        }

        input.count += bytes_read;
        if !success || bytes_read == 0 {
            return copy_string(input);
        }
    }
    return "unreachable";
}

using Toml :: #import, file "../../module.jai";
#import "Basic";
#import "File";
#import "String";
#import "System";
#import "Math";
#import "Unicode";
#if OS == .WINDOWS #import "Windows";
else               #import "POSIX";
