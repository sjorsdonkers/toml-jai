Value :: struct @SumType {
    type :Type= .TABLE;
    union {
        bool_value   : bool = ---;
        int_value    : s64 = ---;
        float_value  : float64 = ---;
        string_value : string = ---;
        datetime     : Chrono = ---;
        array        : [..]Value = ---;
        table        : [..]KeyValue;
    };
    Type :: enum u8 {
        BOOL;
        INT;
        FLOAT;
        STRING;
        DATETIME;
        ARRAY;
        TABLE;
    }
}
KeyValue :: struct {
    key        :  string;
    using value:  Value;
}

copy :: (value: Value) -> Value {
    if #complete value.type == {
    case .BOOL;  #through;
    case .INT;   #through;
    case .FLOAT; #through;
    case .DATETIME; return value;
    case .STRING;   return Value.{type=value.type, string_value=copy_string(value.string_value)};
    case .ARRAY;
        output:= Value.{type=.ARRAY, array=resizable(Value.[])};
        array_reserve(*output.array, value.array.count);
        output.array.count = value.array.count;
        for 0..value.array.count-1 { output.array[it] = copy(value.array[it]); }
        return output;
    case .TABLE;
        output: Value;
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
operator == :: (left: Chrono, right: Chrono) -> bool {
    if left.type != right.type { return false; }
    if #complete left.type == {
    case .LOCAL_TIME; return left.time == right.time;
    case .LOCAL_DATE; return left.date == right.date;
    case .LOCAL_DATETIME; return left.datetime == right.datetime;
    case .OFFSET_DATETIME; return left.datetime_offset == right.datetime_offset;
    }
}
operator == :: (left: Time, right: Time) -> bool {
    return left.hour == right.hour && left.minute == right.minute && left.second == right.second && left.millisecond == right.millisecond;
}
operator == :: (left: Date, right: Date) -> bool {
    return left.year == right.year && left.month == right.month && left.day == right.day;
}
operator == :: (left: DateTime, right: DateTime) -> bool {
    return left.date == right.date && left.time == right.time;
}
operator == :: (left: DateTimeOffset, right: DateTimeOffset) -> bool { // Note exact match
    return left.date == right.date && left.time == right.time && left.offset_hour == right.offset_hour && left.offset_minute == right.offset_minute && left.offset_is_negative == right.offset_is_negative;
}

#load "datetime.jai";
