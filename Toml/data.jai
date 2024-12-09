Value :: struct {
    Type :: enum u8 {
        BOOL;
        INT;
        FLOAT;
        STRING;
        LOCAL_TIME;
        LOCAL_DATE;
        LOCAL_DATETIME;
        OFFSET_DATETIME;
        ARRAY;
        TABLE;
    }
    type: Type;
    union {
        bool_value     : bool;
        int_value      : s64;
        float_value    : float64;
        string_value   : string;
        time           : Time;
        date           : Date;
        datetime       : DateTime;
        datetime_offset: DateTimeOffset;
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
    case .LOCAL_TIME; #through;
    case .LOCAL_DATE; #through;
    case .LOCAL_DATETIME; #through;
    case .OFFSET_DATETIME; return value;
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
    case .BOOL;  return left.bool_value == right.bool_value;
    case .INT;   return left.int_value == right.int_value;
    case .FLOAT; return left.float_value == right.float_value;
    case .STRING; return left.string_value == right.string_value;
    case .LOCAL_TIME; return left.time == right.time;
    case .LOCAL_DATE; return left.date == right.date;
    case .LOCAL_DATETIME; return left.datetime == right.datetime;
    case .OFFSET_DATETIME; return left.datetime_offset == right.datetime_offset;
    case .ARRAY;
        if left.array.count != right.array.count { return false; }
        for left.array {
            if it != right.array[it_index] { return false; }
        }
        return true;
    case .TABLE;
        if left.table.count != right.table.count { return false; }
        for left.table {
            if it != right.table[it_index] { return false; }
        }
        return true;
    }
}

operator == :: (left: KeyValue, right: KeyValue) -> bool {
    return left.key == right.key && left.value == right.value;
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
operator == :: (left: DateTimeOffset, right: DateTimeOffset) -> bool {
    return left.date == right.date && left.time == right.time && left.offset_hour == right.offset_hour && left.offset_minute == right.offset_minute && left.offset_is_negative == right.offset_is_negative;
}

print_value :: (value : Value, indent:="") {
    if #complete value.type == {
    case .STRING; print("'%'", value.string_value);
    case .INT; print("%", value.int_value);
    case .FLOAT; print("%", value.float_value);
    case .BOOL; print("%", value.bool_value);
    // TODO missing leading zeros
    case .LOCAL_TIME; print("%:%:%.%", value.time.hour, value.time.minute, value.time.second, value.time.millisecond);
    case .LOCAL_DATE; print("%-%-%", value.date.year, value.date.month, value.date.day);
    case .LOCAL_DATETIME; print("%-%-%T%:%:%.%", value.datetime.date.year, value.datetime.date.month, value.datetime.date.day, value.datetime.time.hour, value.datetime.time.minute, value.datetime.time.second, value.datetime.time.millisecond);
    case .OFFSET_DATETIME; print("%1-%2-%3T%4:%5:%6.%7%8%9:%10", value.datetime_offset.date.year, value.datetime_offset.date.month, value.datetime_offset.date.day, value.datetime_offset.time.hour, value.datetime_offset.time.minute, value.datetime_offset.time.second, value.datetime_offset.time.millisecond, ifx value.datetime_offset.offset_is_negative then "-" else "+", value.datetime_offset.offset_hour, value.datetime_offset.offset_minute);
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


Time :: struct {
    hour       : u8;
    minute     : u8;
    second     : u8; // can be 60 leap second
    millisecond: u16;
}
Date :: struct {
    year : u16;
    month: u8;
    day  : u8;
}
DateTime :: struct {
    using date: Date;
    using time: Time;
}
DateTimeOffset :: struct {
    using date        : Date;
    using time        : Time;
    offset_hour       : u8;
    offset_minute     : u8;
    offset_is_negative: bool;
}

parse_datetime :: (input: string) -> bool, Value {
    success, time := parse_time(input);
    if success { return true, .{type=.LOCAL_TIME, time=time}; }

    success =, date:= parse_date(input);
    if !success { return false, .{}; }
    if input.count == 10 { return true, .{type=.LOCAL_DATE, date=date}; }

    // Must be datetime [offset]
    if input.count < 19 { return false, .{}; }

    // TODO get space with next token
    if input[10] != #char "T" && input[10] != #char " " { return false, .{}; } // NOTE: TOML does not allow lowercase T/Z
    time_str := slice(input, 11, input.count-11);

    if input[input.count-1] == #char "Z" {
        success, time = parse_time(slice(time_str, 0, time_str.count-1));
        if !success { return false, .{}; }
        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=0, offset_minute=0}};
    } else if input[input.count-6] == #char "+" || input[input.count-6] == #char "-" {
        success, time = parse_time(slice(time_str, 0, time_str.count-6));
        if !success { return false, .{}; }

        offset_is_negative := input[input.count-6] == #char "-";
        offset_hour := slice_to_int(time_str, time_str.count-5, 2, u8, Value);
        if time_str[time_str.count-3] != #char ":" { return false, .{}; }
        offset_minute := slice_to_int(time_str, time_str.count-2, 2, u8, Value);

        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=offset_hour, offset_minute=offset_minute, offset_is_negative=offset_is_negative}};
    } else {
        success, time = parse_time(time_str);
        if !success { return false, .{}; }
        return true, .{type=.LOCAL_DATETIME, datetime=.{date=date, time=time}};
    }
}

parse_time :: (input: string) -> bool, Time {
    if input.count < 8 { return false, .{}; }
    if input[2] != #char ":" || input[5] != #char ":" { return false, .{}; }
    hour   := slice_to_int(input, 0, 2, u8, Time);
    minute := slice_to_int(input, 3, 2, u8, Time);
    second := slice_to_int(input, 6, 2, u8, Time);
    millisecond :u16=0;
    if input.count > 8 {
        if input[8] != #char "." { return false, .{}; }
        ms_digit_count := min(3, input.count - 9);
        millisecond  = slice_to_int(input, 9, ms_digit_count, u16, Time);
        ignored     := slice_to_int(input, 9 + ms_digit_count, input.count - 9 - ms_digit_count, u64, Time);
    }
    return true, Time.{hour=hour, minute=minute, second=second, millisecond=millisecond};
}

parse_date :: (input: string) -> bool, Date {
    if input.count < 10 { return false, .{}; }
    if input[4] != #char "-" || input[7] != #char "-" { return false, .{}; }
    year  := slice_to_int(input, 0, 4, u16, Date);
    month := slice_to_int(input, 5, 2, u8,  Date);
    day   := slice_to_int(input, 8, 2, u8,  Date);
    return true, Date.{year=year, month=month, day=day};
}

// #scope_file

slice_to_int :: (input: string, start: s64, size: s64, $Target: Type, $Returns: Type) -> Target #expand {
    output, success, remainder := string_to_int(slice(input, start, size), 10, Target);
    if !success || remainder.count != 0 { `return false, Returns.{}; }
    return output;
}

#import "Basic";
#import "String";

main :: () {
    // {
    //     success, time := parse_datetime("12:34:56.78912");
    //     if !success { print("Failed to parse time\n"); return; }
    //     print_value(time);
    // }
    // {
    //     success, date := parse_datetime("2020-12-31");
    //     if !success { print("Failed to parse date\n"); return; }
    //     print_value(date);
    // }
    {
        success, date := parse_datetime("1979-05-27T00:32:00.999999-07:00");
        if !success { print("Failed to parse date\n"); return; }
        print_value(date);
    }
}
