Value :: struct {
    Type :: enum u8 {
        BOOL;
        INT;
        FLOAT;
        STRING;
        DATETIME;
        ARRAY;
        TABLE;
    }
    type: Type;
    union {
        bool_value     : bool;
        int_value      : s64;
        float_value    : float64;
        string_value   : string;
        datetime       : string;
        array          : [..]Value;
        table          : [..]KeyValue;
    };
}
KeyValue :: struct {
    key        :  string;
    using value:  Value;
}

copy :: (value: Value) -> Value {
    if #complete value.type == {
    case .BOOL; #through;
    case .INT;  #through;
    case .FLOAT;  return value;
    case .DATETIME; #through;
    case .STRING; return Value.{type=value.type, string_value=copy_string(value.string_value)};
    case .ARRAY;
        output:= Value.{type=.ARRAY, array=resizable(Value.[])};
        array_copy(*output.array, value.array);
        return output;
    case .TABLE;
        output:= Value.{type=.TABLE, table=resizable(KeyValue.[])};
        array_copy(*output.table, value.table);
        return output;
    }
}

operator == :: (left: Value, right: Value) -> bool {
    if left.type != right.type { return false; }
    if #complete left.type == {
    case .BOOL;     return left.bool_value   == right.bool_value;
    case .INT;      return left.int_value    == right.int_value;
    case .FLOAT;    return left.float_value  == right.float_value;
    case .STRING;   return left.string_value == right.string_value;
    case .DATETIME; return left.datetime     == right.datetime;
    case .ARRAY;
        if left.array.count != right.array.count { return false; }
        for left.array { if it != right.array[it_index] { return false; } }
        return true;
    case .TABLE;
        if left.table.count != right.table.count { return false; }
        for left.table { if it != right.table[it_index] { return false; } }
        return true;
    }
}

operator == :: (left: KeyValue, right: KeyValue) -> bool {
    return left.key == right.key && left.value == right.value;
}

print_value :: (value : Value, indent:="") {
    if #complete value.type == {
    case .STRING; print("'%'", value.string_value);
    case .INT; print("%", value.int_value);
    case .FLOAT; print("%", value.float_value);
    case .BOOL; print("%", value.bool_value);
    case .DATETIME; print("%", value.datetime);
    case .ARRAY;
        print("[\n");
        new_indent := tprint("%  ", indent);
        for val: value.array {
            print("%", new_indent);
            print_value(val, new_indent);
            print(",\n");
        }
        print("%]", indent);
    case .TABLE;
        print("{\n");
        new_indent := tprint("%  ", indent);
        for keyval: value.table {
            print("%0% ", new_indent, keyval.key);
            if keyval.type != .TABLE { print("= "); }
            print_value(keyval.value, new_indent);
            print("\n");
        }
        print("%}", indent);
    }
}
