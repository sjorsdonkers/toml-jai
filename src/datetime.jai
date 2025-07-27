// Toml dates / times which are based on RFC 3339
// https://datatracker.ietf.org/doc/html/rfc3339
// These types are to be removed when there is a commonly used datetime module in Jai

Chrono :: struct @SumType {
    type: Type;
    union {
        time: Time;
        date: Date = ---;
        datetime: DateTime = ---;
        datetime_offset: DateTimeOffset = ---;
    };
    Type :: enum u8 {
        LOCAL_TIME;
        LOCAL_DATE;
        LOCAL_DATETIME;
        OFFSET_DATETIME;
    }
}
Time :: struct {
    hour       : u8;
    minute     : u8;
    second     : u8;
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

// Parses a datetime in the format "YYYY-MM-DDTHH:MM:SS[.SSS][Z|(+|-)HH:MM]"
parse_datetime :: (input: string) -> ok:=false, value:Chrono=.{} {
    success, time := parse_time(input);
    if success { return true, .{type=.LOCAL_TIME, time=time}; }

    success =, date:= parse_date(input); if !success return;
    if input.count == 10 { return true, .{type=.LOCAL_DATE, date=date}; }

    // Must be datetime [offset]
    if input.count < 19 return;
    if input[10] != "T" && input[10] != "t" && input[10] != " " return; // NOTE: TOML does not allow lowercase T
    time_str := slice(input, 11, input.count-11);

    if time_str[time_str.count-1] == "Z" || time_str[time_str.count-1] == "z" {
        // Datetime with Zulu time
        success, time = parse_time(slice(time_str, 0, time_str.count-1)); if !success return;
        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=0, offset_minute=0}};
    } else if time_str[time_str.count-6] == "+" || time_str[time_str.count-6] == "-" {
        // Datetime with timezone by offset
        success, time = parse_time(slice(time_str, 0, time_str.count-6)); if !success return;

        offset_is_negative := time_str[time_str.count-6] == "-";
        offset_hour := slice_to_int(time_str, time_str.count-5, 2, u8);
        if time_str[time_str.count-3] != ":" return;
        offset_minute := slice_to_int(time_str, time_str.count-2, 2, u8);

        return true, .{type=.OFFSET_DATETIME, datetime_offset=.{date=date, time=time, offset_hour=offset_hour, offset_minute=offset_minute, offset_is_negative=offset_is_negative}};
    } else {
        // Datetime without timezone
        success, time = parse_time(time_str); if !success return;
        return true, .{type=.LOCAL_DATETIME, datetime=.{date=date, time=time}};
    }
}

// Parses a time in the format "HH:MM:SS[.SSS]", extra characters may only be digits
parse_time :: (input: string) -> ok:=false, value:Time=.{} {
    if input.count < 8 return;
    if input[2] != ":" || input[5] != ":" return;
    hour   := slice_to_int(input, 0, 2, u8);
    minute := slice_to_int(input, 3, 2, u8);
    second := slice_to_int(input, 6, 2, u8);
    millisecond :u16=0;
    if input.count > 8 {
        if input[8] != "." return;
        ms_digit_count := min(3, input.count - 9);
        millisecond  = slice_to_int(input, 9, ms_digit_count, u16);
        if ms_digit_count > 3 { // We only store the minimum required precision to support (milliseconds)
            ignored     := slice_to_int(input, 9 + ms_digit_count, input.count - 9 - ms_digit_count, u64);
        }
    }
    return true, Time.{hour=hour, minute=minute, second=second, millisecond=millisecond};
}

// Parses a date in the format "YYYY-MM-DD", extra characters are ignored
parse_date :: (input: string) -> ok:=false, value:Date=.{} {
    if input.count < 10 return;
    if input[4] != "-" || input[7] != "-" return;
    year  := slice_to_int(input, 0, 4, u16);
    month := slice_to_int(input, 5, 2, u8);
    day   := slice_to_int(input, 8, 2, u8);
    return true, Date.{year=year, month=month, day=day};
}

// Formats a time to a string in the format "HH:MM:SS.SSS"
print_time_to_builder :: (builder: *String_Builder, time: Time) {
    print_integer(builder, formatInt(time.hour, minimum_digits=2));
    append(builder, ":");
    print_integer(builder, formatInt(time.minute, minimum_digits=2));
    append(builder, ":");
    print_integer(builder, formatInt(time.second, minimum_digits=2));
    append(builder, ".");
    print_integer(builder, formatInt(time.millisecond, minimum_digits=3));
}
// Formats a date to a string in the format "YYYY-MM-DD"
print_date_to_builder :: (builder: *String_Builder, date: Date) {
    print_integer(builder, formatInt(date.year, minimum_digits=4));
    append(builder, "-");
    print_integer(builder, formatInt(date.month, minimum_digits=2));
    append(builder, "-");
    print_integer(builder, formatInt(date.day, minimum_digits=2));
}
// Formats a datetime to a string in the format "YYYY-MM-DDTHH:MM:SS.SSS"
print_datetime_to_builder :: (builder: *String_Builder, datetime: DateTime) {
    print_date_to_builder(builder, datetime.date);
    append(builder, "T");
    print_time_to_builder(builder, datetime.time);
}
// Formats a datetime offset to a string in the format "YYYY-MM-DDTHH:MM:SS.SSSZ|(+|-)HH:MM"
print_datetime_offset_to_builder :: (builder: *String_Builder, datetime_offset: DateTimeOffset) {
    print_date_to_builder(builder, datetime_offset.date);
    append(builder, "T");
    print_time_to_builder(builder, datetime_offset.time);
    append(builder, ifx datetime_offset.offset_is_negative then "-" else "+");
    print_integer(builder, formatInt(datetime_offset.offset_hour, minimum_digits=2));
    append(builder, ":");
    print_integer(builder, formatInt(datetime_offset.offset_minute, minimum_digits=2));
}
// Formats a chrono to a string based on its type
print_datetime_to_builder :: (builder: *String_Builder, chrono: Chrono) {
    if #complete chrono.type == {
    case .LOCAL_TIME; print_time_to_builder(builder, chrono.time);
    case .LOCAL_DATE; print_date_to_builder(builder, chrono.date);
    case .LOCAL_DATETIME; print_datetime_to_builder(builder, chrono.datetime);
    case .OFFSET_DATETIME; print_datetime_offset_to_builder(builder, chrono.datetime_offset);
    }
}

#scope_file

// Attempts to extract a sub-string to an integer, returns from the callers scope on failure
// string_to_int is not checked as is is expected to be called with s small number of characters relative to the Target
slice_to_int :: (input: string, start: s64, size: s64, $Target: Type) -> Target #expand {
    output, success, remainder := string_to_int(slice(input, start, size), 10, Target);
    if !success || remainder.count != 0 { `return; }
    return output;
}

#import "Basic";
#import "String";
