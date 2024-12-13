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
        array_reserve(*output.array, value.array.count);
        output.array.count = value.array.count;
        for 0..value.array.count-1 { output.array[it] = copy(value.array[it]); }
        return output;
    case .TABLE;
        output:= Value.{type=.TABLE, table=resizable(KeyValue.[])};
        array_reserve(*output.table, value.table.count);
        output.table.count = value.table.count;
        for 0..value.table.count-1 { output.table[it] = copy(value.table[it]); }
        return output;
    }
}
copy :: (keyvalue: KeyValue) -> KeyValue {
    return KeyValue.{key=copy_string(keyvalue.key), value=copy(keyvalue.value)};
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
