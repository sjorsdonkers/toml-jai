serialize :: (value: Value) -> string {
    builder: String_Builder;
    serialize(*builder, value);
    return builder_to_string(*builder);
}

serialize :: (builder: *String_Builder, value: Value) {
    assert(value.type == .TABLE);
    for value.table {
        print_to_builder_escaped(builder, it.key);
        append(builder, "=");
        serialize(it.value, builder);
        append(builder, "\n");
    }
}

#scope_file

serialize :: (value: Value, builder: *String_Builder) {
    if #complete value.type == {
    case .BOOL; print_item_to_builder(builder, value.bool_value);
    case .INT;  print_item_to_builder(builder, value.int_value);
    case .FLOAT;
        tmp := tprint("%", value.float_value);
        to_lower_in_place(tmp); // for Inf->inf / NaN->nan
        print_item_to_builder(builder, tmp);
    case .STRING;   print_to_builder_escaped(builder, value.string_value);
    case .DATETIME; print_item_to_builder(builder, value.datetime);
    case .ARRAY;
        append(builder, "[");
        for value.array {
            serialize(it, builder);
            append(builder, ",");
        }
        append(builder, "]");
    case .TABLE;
        // TODO empty table
        append(builder, "{");
        for value.table {
            print_to_builder_escaped(builder, it.key);
            append(builder, "=");
            serialize(it.value, builder);
            if it_index + 1 != value.table.count then append(builder, ",");
        }
        append(builder, "}");
    }
}

#scope_file

print_to_builder_escaped :: (builder: *String_Builder, str: string) {
    append(builder, "\"");
	for str if it == { // @speed
        case #char "\x08"; append(builder, "\\b");
        case #char "\t";   append(builder, "\\t");
        case #char "\n";   append(builder, "\\n");
        case #char "\x0c"; append(builder, "\\f");
        case #char "\r";   append(builder, "\\r");
        case #char "\"";   append(builder, "\\\"");
        case #char "\\";   append(builder, "\\\\");
        case;              append(builder, it);
    }
    append(builder, "\"");
}

#import "Basic";
