
main :: () {
TIME_STRING :: #string DONE
# Offset date time
odt1 = 1979-05-27T07:32:00Z
odt2 = 1979-05-27T00:32:00-07:00
odt3 = 1979-05-27T00:32:00.999999-07:00

odt4 = 1979-05-27 07:32:00Z

# Local date time
ldt1 = 1979-05-27T07:32:00
ldt2 = 1979-05-27T00:32:00.999999

# Local date
ld1 = 1979-05-27

# Local time
lt1 = 07:32:00
lt2 = 00:32:00.999999
DONE
    right := Toml.deserialize(TIME_STRING, Toml.Value);
    print_value(right);
}

using Toml :: #import, file "../Toml/module.jai";
#import "Basic";
#import "File";
