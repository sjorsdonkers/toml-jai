// Toml dates / times which are based on RFC 3339
// https://datatracker.ietf.org/doc/html/rfc3339

Chrono :: struct {
    union {
        time: Time;
        date: Date;
        datetime: DateTime;
        datetime_offset: DateTimeOffset;
    };
    Type :: enum u8 {
        LOCAL_TIME;
        LOCAL_DATE;
        LOCAL_DATETIME;
        OFFSET_DATETIME;
    }
    type: Type;
}
Time :: struct {
    hour       : u8;
    minute     : u8;
    second     : u8; // Can be 60, leap second
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

parse_datetime :: (input: string) -> success:bool=false, value:Chrono=.{} {
    success, time := parse_time(input);
    if success { return true, .{type=.LOCAL_TIME, time=time}; }

    success =, date:= parse_date(input); if !success return;
    if input.count == 10 { return true, .{type=.LOCAL_DATE, date=date}; }

    // Must be datetime [offset]
    if input.count < 19 return;
    if input[10] != #char "T" && input[10] != #char " " return; // NOTE: TOML does not allow lowercase T
    time_str := slice(input, 11, input.count-11);

    if time_str[time_str.count-1] == #char "Z" { // NOTE: TOML does not allow lowercase Z
        success, time = parse_time(slice(time_str, 0, time_str.count-1)); if !success return;
        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=0, offset_minute=0}};
    } else if time_str[time_str.count-6] == #char "+" || time_str[time_str.count-6] == #char "-" {
        success, time = parse_time(slice(time_str, 0, time_str.count-6)); if !success return;

        offset_is_negative := time_str[time_str.count-6] == #char "-";
        offset_hour := slice_to_int(time_str, time_str.count-5, 2, u8);
        if time_str[time_str.count-3] != #char ":" return;
        offset_minute := slice_to_int(time_str, time_str.count-2, 2, u8);

        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=offset_hour, offset_minute=offset_minute, offset_is_negative=offset_is_negative}};
    } else {
        success, time = parse_time(time_str); if !success return;
        return true, .{type=.LOCAL_DATETIME, datetime=.{date=date, time=time}};
    }
}

parse_time :: (input: string) -> success:bool=false, value:Time=.{} {
    if input.count < 8 return;
    if input[2] != #char ":" || input[5] != #char ":" return;
    hour   := slice_to_int(input, 0, 2, u8);
    minute := slice_to_int(input, 3, 2, u8);
    second := slice_to_int(input, 6, 2, u8);
    millisecond :u16=0;
    if input.count > 8 {
        if input[8] != #char "." return;
        ms_digit_count := min(3, input.count - 9);
        millisecond  = slice_to_int(input, 9, ms_digit_count, u16);
        ignored     := slice_to_int(input, 9 + ms_digit_count, input.count - 9 - ms_digit_count, u64);
    }
    return true, Time.{hour=hour, minute=minute, second=second, millisecond=millisecond};
}

parse_date :: (input: string) -> success:bool=false, value:Date=.{} {
    if input.count < 10 return;
    if input[4] != #char "-" || input[7] != #char "-" return;
    year  := slice_to_int(input, 0, 4, u16);
    month := slice_to_int(input, 5, 2, u8);
    day   := slice_to_int(input, 8, 2, u8);
    return true, Date.{year=year, month=month, day=day};
}

#scope_file

slice_to_int :: (input: string, start: s64, size: s64, $Target: Type) -> Target #expand {
    output, success, remainder := string_to_int(slice(input, start, size), 10, Target);
    if !success || remainder.count != 0 { `return; }
    return output;
}

#import "Basic";
#import "String";
