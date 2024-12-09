Chrono :: struct {
    Type :: enum u8 {
        LOCAL_TIME;
        LOCAL_DATE;
        LOCAL_DATETIME;
        OFFSET_DATETIME;
    }
    type: Type;
    union {
        time: Time;
        date: Date;
        datetime: DateTime;
        datetime_offset: DateTimeOffset;
    };
}
Time :: struct {
    hour       : u8;
    minute     : u8;
    second     : u8; // Can be 60 leap second
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

parse_datetime :: (input: string) -> bool, Chrono {
    success, time := parse_time(input);
    if success { return true, .{type=.LOCAL_TIME, time=time}; }

    success =, date:= parse_date(input);
    if !success { return false, .{}; }
    if input.count == 10 { return true, .{type=.LOCAL_DATE, date=date}; }

    // Must be datetime [offset]
    if input.count < 19 { return false, .{}; }

    // TODO get space with next token
    if input[10] != #char "T" && input[10] != #char " " { return false, .{}; } // NOTE: TOML does not allow lowercase T
    time_str := slice(input, 11, input.count-11);

    if input[input.count-1] == #char "Z" { // NOTE: TOML does not allow lowercase Z
        success, time = parse_time(slice(time_str, 0, time_str.count-1));
        if !success { return false, .{}; }
        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=0, offset_minute=0}};
    } else if input[input.count-6] == #char "+" || input[input.count-6] == #char "-" {
        success, time = parse_time(slice(time_str, 0, time_str.count-6));
        if !success { return false, .{}; }

        offset_is_negative := input[input.count-6] == #char "-";
        offset_hour := slice_to_int(time_str, time_str.count-5, 2, u8, Chrono);
        if time_str[time_str.count-3] != #char ":" { return false, .{}; }
        offset_minute := slice_to_int(time_str, time_str.count-2, 2, u8, Chrono);

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

#scope_file

slice_to_int :: (input: string, start: s64, size: s64, $Target: Type, $Returns: Type) -> Target #expand {
    output, success, remainder := string_to_int(slice(input, start, size), 10, Target);
    if !success || remainder.count != 0 { `return false, Returns.{}; }
    return output;
}

#import "Basic";
#import "String";
