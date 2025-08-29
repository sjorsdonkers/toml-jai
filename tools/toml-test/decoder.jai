main :: () {
    push_allocator(temp);

    toml_data := stdinput();
    ok, parsed_toml := Toml.string_to_value_shared_memory(toml_data);
    if !ok {
        print("Failed to parse TOML data\n", to_standard_error=true);
        exit(1);
    }

    builder: String_Builder;
    value_to_json(*builder, parsed_toml);
    write_builder(*builder, false);
}

value_to_json :: (builder: *String_Builder, value: Toml.Value) {
    if #complete value.type == {
    case .BOOL;  print_to_builder(builder, "{\"type\":\"bool\",\"value\":\"%\"}",    value.bool_value);
    case .INT;   print_to_builder(builder, "{\"type\":\"integer\",\"value\":\"%\"}", value.int_value);
    case .FLOAT;
        mode := FormatFloat.Mode.DECIMAL;
        ifx value.float_value < (1.0e-6) then mode = .SCIENTIFIC;
        tmp := sprint("%", FormatFloat.{value=value.float_value, trailing_width=15, mode = mode});
        print_to_builder(builder, "{\"type\":\"float\",\"value\":\"%\"}", trim(tmp));
    case .STRING;
        append(builder, "{\"type\":\"string\",\"value\":");
        json_escape_string(builder, value.string_value);
        append(builder, "}");
    case .DATETIME;
        if #complete value.datetime.type == {
            case .LOCAL_TIME;      append(builder, "{\"type\":\"time-local\",\"value\":\"");
            case .LOCAL_DATE;      append(builder, "{\"type\":\"date-local\",\"value\":\"");
            case .LOCAL_DATETIME;  append(builder, "{\"type\":\"datetime-local\",\"value\":\"");
            case .OFFSET_DATETIME; append(builder, "{\"type\":\"datetime\",\"value\":\"");
        }
        print_datetime_to_builder(builder, value.datetime);
        append(builder, "\"}");
    case .ARRAY;
        append(builder, "[\n");
        for value.array {
            if it_index > 0 append(builder, ",\n");
            value_to_json(builder, it);
        }
        append(builder, "]");
    case .TABLE;
        append(builder, "{");
        for value.table {
            if it_index > 0 append(builder, ",\n");
            json_escape_string(builder, it.key);
            append(builder, ":");
            value_to_json(builder, it.value);
        }
        append(builder, "}");
    case .FORMAT_INT; #through;
    case .FORMAT_FLOAT;
        assert(false, "FORMAT types should not appear in parsed TOML data");
    }
}

json_escape_string :: (builder: *String_Builder, str: string) {
    append(builder, "\"");
    for char: cast([]u8)str {
        if char == {
        case #char "\"";   append(builder, "\\\"");
        case #char "\\";   append(builder, "\\\\");
        case #char "\x08"; append(builder, "\\b");
        case #char "\x0c"; append(builder, "\\f");
        case #char "\n";   append(builder, "\\n");
        case #char "\r";   append(builder, "\\r");
        case #char "\t";   append(builder, "\\t");
        case;
            if char < 32 {
                // Manual hex formatting to ensure 4 digits with leading zeros
                hex_digits := "0123456789abcdef";
                append(builder, "\\u");
                append(builder, hex_digits[(char >> 12) & 0xF]);
                append(builder, hex_digits[(char >> 8) & 0xF]);
                append(builder, hex_digits[(char >> 4) & 0xF]);
                append(builder, hex_digits[char & 0xF]);
            }
            else append(builder, char);
        }
    }
    append(builder, "\"");
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
#if OS == .WINDOWS #import "Windows";
else               #import "POSIX";
