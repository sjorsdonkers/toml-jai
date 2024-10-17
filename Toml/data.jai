Value_Type :: enum u8 {
    BOOL;
    INT;
    FLOAT;
    STRING;
    ARRAY;
    TABLE;
}

Value :: struct {
    type: Value_Type;
    union {
        bool_value  : bool;
        int_value   : s64;
        float_value : float64;
        string_value: string;
        array       : [..]Value;
        table       : [..]KeyValue;
    };
}
KeyValue :: struct {
    key        :  string;
    using value:  Value;
}
