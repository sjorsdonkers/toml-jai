Value :: struct {
    type :Type= .TABLE;
    index_map_id: s32 = -1;  // Index into context.toml.index_maps array, -1 means no index map
    union {
        bool_value   : bool         = ---;
        int_value    : s64          = ---;
        float_value  : float64      = ---;
        string_value : string       = ---;
        datetime     : Chrono       = ---;
        array        : [..]Value    = ---;
        table        : [..]KeyValue;
        format_int   : *FormatInt   = ---; // Only for serialization, * to reduce size
        format_float : *FormatFloat = ---; // Only for serialization, * to reduce size
    };
    Type :: enum u8 {
        BOOL;
        INT;
        FLOAT;
        STRING;
        DATETIME;
        ARRAY;
        TABLE;
        FORMAT_INT;   // Only for serialization
        FORMAT_FLOAT; // Only for serialization
    }
}
KeyValue :: struct {
    key        :  string;
    using value:  Value;
}

// Uses index when available, if index_map_id is set entry must exist in index_maps
table_find_value_by_key :: (table: *Value, key: string, index_maps: []Table(string, s64)) -> found:=false, table:*Value=null {
    assert(table.type == .TABLE);
    if table.index_map_id < 0 { // Linear search for small tables
        for table.table if it.key == key { return true, *it.value; }
    } else {                    // Use hash lookup for large tables
        index_map    := *index_maps[table.index_map_id];
        found, index := table_find_new(index_map, key);
        if found { return true, *table.table[index].value; }
    }
    return false;               // Not found
}

copy :: (value: Value) -> Value {
    if #complete value.type == {
    case .BOOL;  #through;
    case .INT;   #through;
    case .FLOAT; #through;
    case .DATETIME; return value;
    case .STRING;   return Value.{type=.STRING, string_value=copy_string(value.string_value), index_map_id=value.index_map_id};
    case .ARRAY;
        output:= Value.{type=.ARRAY, array=[..]Value.{}, index_map_id=value.index_map_id};
        array_reserve(*output.array, value.array.count);
        output.array.count = value.array.count;
        for 0..value.array.count-1 { output.array[it] = copy(value.array[it]); }
        return output;
    case .TABLE;
        output: Value;
        output.index_map_id = value.index_map_id;
        array_reserve(*output.table, value.table.count);
        output.table.count = value.table.count;
        for 0..value.table.count-1 { output.table[it] = copy(value.table[it]); }
        return output;
    case .FORMAT_INT;   return Value.{type=.FORMAT_INT,   format_int  =copy(value.format_int  ), index_map_id=value.index_map_id};
    case .FORMAT_FLOAT; return Value.{type=.FORMAT_FLOAT, format_float=copy(value.format_float), index_map_id=value.index_map_id};
    }
}
copy :: (keyvalue: KeyValue) -> KeyValue {
    return KeyValue.{key=copy_string(keyvalue.key), value=copy(keyvalue.value)};
}
copy :: (format: *FormatFloat) -> *FormatFloat {
    clone := New(FormatFloat, false);
    clone.* = format.*;
    memory := alloc(clone.value.type.runtime_size);
    memcpy(memory, format.value.value_pointer, clone.value.type.runtime_size);
    clone.value.value_pointer = memory;
    return clone;
}
copy :: (format: *FormatInt) -> *FormatInt {
    clone := New(FormatInt, false);
    clone.* = format.*;
    memory := alloc(clone.value.type.runtime_size);
    memcpy(memory, format.value.value_pointer, clone.value.type.runtime_size);
    clone.value.value_pointer = memory;
    clone.comma_string = copy_string(format.comma_string);
    return clone;
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
    case .FORMAT_INT;
        if left.format_int.value.type != right.format_int.value.type { return false; }
        if left.format_int.value.value_pointer == null || right.format_int.value.value_pointer == null {
            return left.format_int.value.value_pointer == right.format_int.value.value_pointer;
        }
        return 0 == memcmp(left.format_int.value.value_pointer, right.format_int.value.value_pointer, left.format_int.value.type.runtime_size);
    case .FORMAT_FLOAT;
        if left.format_float.value.type != right.format_float.value.type { return false; }
        if left.format_float.value.value_pointer == null || right.format_float.value.value_pointer == null {
            return left.format_float.value.value_pointer == right.format_float.value.value_pointer;
        }
        return 0 == memcmp(left.format_float.value.value_pointer, right.format_float.value.value_pointer, left.format_float.value.type.runtime_size);
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
