# TOML-jai

![](https://img.shields.io/badge/Jai-beta%200.2.026-blue.svg)

A module for `TOML v1.0.0` support. It provides functionality to read/write TOML files and convert them directly to/from Jai data structures.

- Full TOML v1.0.0 support.
- All run-time data types are supported as their native type including reference types (`pointer`, `array`, `any`), with the exception of `untagged unions`.
- Generic data is supported through the [Toml.Value](src/data.jai) struct.
- Dates/times are supported types provided in [datetime.jai](src/datetime.jai) (until Jai has native types, Apollo_time.Calendar_Time is not usable here).
- Modifying the default behavior like: renaming, omitting, changing Type representation like Hash_Tables, enum as int, extra validation, or handling complex data like binary encodings are supported through [custom handlers](examples/custom_handlers.jai). 

## Deserialize
```jai
ok, my_struct := Toml.string_to_type(toml_string, My_Struct);
```
- Read TOML directly into any (nested) struct or generic `Toml.Value`.
- Any field missing in the TOML fails unless annotated with `@serialize:default` or `#overlay` members. Any superfluous fields in the TOML are ignored.
- Compile-time constants are ignored and not compared.
- The parser assures the input is fully [TOML spec](https://toml.io/en/v1.0.0) compliant.

## Serialize
```jai
ok, toml_string := Toml.type_to_string(my_struct);
```
- Write any (nested) struct or `Toml.Value` to TOML string.
- Null pointers/null Anys by default are written as `"~null~"`, this can be controlled via the context member `toml.null_value`.
- Compile-time `constants` & `imports` as well as `#overlay` members are skipped.

## Error handling
Success -> bool  
Error message -> interceptable logger
- Asserts are used to confirm correct implementation of the module. A triggered assert indicates a bug.
- Input data errors are flagged by the return boolean indicating the success of the operation. If a procedure indicates failure the reason will be found in the error log.
- To prevent the TOML module from writing to the error log or to redirect it, the user can set a catching or wrapping logger in the context, see [examples](examples/first.jai).

## Memory management & lifetime
Set a context.allocator:
```jai
Toml.string_to_type(toml_string, My_Struct,, my_alloc);
defer release(my_alloc);
```
Dynamically sized data like arrays and strings are returned on the provided context allocator. As such, the safe lifetime of all returned objects ends when the memory of the allocator is released.
- Allocation for returned data are in the context allocator. Instead of free_x() or deinit_x() procedures the user is expected to push an allocator such that all data can be dropped together.
- None of the returned data references allocated data of the input arguments (except `*_shared_memory` procedures).
- The `temp` allocator is used for intermediate data and error messages, `temp` is released back to the storage mark it started at (unless the `context.allocator` was set to `temp`).
- In most cases this means that only the returned data will be left allocated on the context allocator.

## Custom handlers
By default this Toml modules makes several choices like, enums as string, members serialized by their name, no members omitted, etc.
These choices may be fine for the large majority of use-cases but not all. Custom handlers enable the user to modify the serialization/deserialization of types.
Custom handlers follow the same design as `Print_Style.struct_printer`, except instead of writing to the builder it returns the Toml.Value to be written.

Note that these custom handler drive "what" is serialized, they do not help with formatting of the toml. Formatting can be controlled via `toml.default_format_int` / `toml.default_format_float` in the context, see the [formatting example](examples/formatting_control.jai).

Serialization can be modified by changing the custom handler procedure in the context.
```jai
enum_to_value :: (input: Any) -> ok:=false, toml:Value=.{} {
    if input.type.type != .ENUM {
        ok, value := Toml.default_type_to_value(input); // Types we do not handle here continue in normal flow
        return ok, value;
    }
    enum_value := Reflection.get_enum_value(input.value_pointer, xx input.type);
    return true, Toml.Value.{kind=.INT, int_value=enum_value};
}

ok, toml := Toml.type_to_string(
    my_struct
    ,, toml = .{custom_type_to_value=enum_to_value}
);
```

## Testing
> The `jai` and optionally `toml-test` executables should be in the PATH.

```sh
jai ./tests.jai
```
The module is tested by compiling and running the examples. The command above does that for all examples. It will also run the tests from `toml-test` if the executable can be found in the PATH or the [tools/toml-test](tools/toml-test) directory.

## Implementation

### Two-step (de)serialization
The module supports both Typed as well as Generic data using Toml.Value. To avoid having to maintain 2 implementations the Typed version is implemented by going through the Generic version. As a result there are some extra data copies/allocations as well as limitations like no support for integers > S64_MAX and slightly reduced accuracy for float due to intermediate conversion through float64.

### Type reflection
We only have a run-time reflection based implementation, e.g. Any based like: `value_to_type :: (toml: Value, output: Any)`. A compile-time reflection based implementation, see the [comptime branch](https://github.com/sjorsdonkers/toml-jai/tree/comptime), that has the types determined at compile-time like `value_to_type :: (toml: Value, data: *$T)` would have slightly cleaner code, better run-time performance, and can handle generic custom types (like `Hash_Table`) more conveniently, but it does not support dynamic types like Any, and custom handlers become more complex, with module parameters, code insertion and`#poke_name`. Having multiple implementations is considered undesirable. Switching to compile-time reflection should be reevaluated when the `#poke_name` replacement has landed in Jai.

### Customization points
Custom handlers have several design goals:
 - Keep the core Toml module implementation clean from complexity.
 - Enable custom serialization of types we do not own (external Modules) as we may not be able to add notes or remove members.
 - The same type should be serializable in different ways defined at the procedure call site, not struct definition.
 - Enable data tweaks during serialization as opposed to full data copies of nested structure trees (separate structs for serialization and usage within the application).
 - The user should be able to opt-out of the default behavior of handling special types like Toml.Value, Chrono. A user can opt-out by setting a procedure that does not call the default_custom_handler.

In addition to handlers we currently also support making struct members optional through a `@serialize:default` note. This means there are 2 ways to do the same thing, the note also requires the original Type(_Info) to be modified. It is likely this note will be removed when these kinds of operations are better supported through custom handlers.

The context member `toml.null_value` is introduced as a customization point as it would otherwise be relatively complicated to catch all cases where pointers can occur. toml.null_value can be any kind of Toml.Value, by default it is a string of value `"~null~"`. Deserialization of the value `"~null~"` for a `*string` member can be surprising as it would result into a null pointer instead of a string with value `"~null~"`. The `~`s are added to make it a string that is less likely to occur naturally.
Alternative sentinel values like the empty table `{}` which is the equivalent of a struct without members are not chosen as due to `@serialize:default` it is also equivalent to a struct with all optional members.

### Lexer
The tokenization/lexer phase completes before the parser starts. As a result memory needs to be allocated to store the tokens. There is no particular reason for this implementation other than that I wanted to experiment with this type of lexer. Unlike traditional lexers the one implemented here does not parse the tokens into literals like int/float/etc it just determines the ranges for strings and token scopes. It is the responsibility of the parser to interpret the string when it has more context.
