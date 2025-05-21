# TOML-jai

![](https://img.shields.io/badge/Jai-beta%200.2.012-blue.svg)

A module for `TOML v1.0.0` support. It provides functionality to read/write TOML files and convert them directly to/from Jai data structures.

- Full TOML v1.0.0 support.
- All run-time data types are supported as their native type including reference types (`pointer`, `array`, `any`), with the exception of `untagged unions`.
- Generic data is supported through the [Toml.Value](src/data.jai) struct.
- Dates/times are supported types provided in [src/datetime.jai](src/datetime.jai) (until Jai has native types, Apollo_time.Calendar_Time is not usable here).
- Safe sum-types with `@SumType` notes to indicate the struct has a tag enum followed by a matching union.
- Modifying the default behavior, like renaming, omitting, changing Type representation like Hash_Tables, enum as int, extra validation, or handling complex data like binary encodings are supported through [custom handlers](examples/custom_handlers.jai). 

## Deserialize
`ok, my_struct := Toml.deserialize(toml_string, My_Struct);`
- Read TOML directly into any (nested) struct or generic `Toml.Value`.
- Any field not in the TOML fails unless annotated with `@TomlOptional`. Any superfluous fields in the TOML are ignored.
- Compile-time constants are ignored and not compared.
- If the parser understands the input it will accept it even if it is officially invalid according to the standard. This may in the future change to be more strict. See the [validation example](examples/validation.jai) for more details.

## Serialize
`ok, toml_string := Toml.serialize(my_struct);`
- Write any (nested) struct or `Toml.Value` to TOML string.
- Null pointers/null Anys by default are written as `"~null~"`, this can be controlled via the context member `toml_null_value`.
- Compile-time `constants` & `imports` are skipped.
- `#place` members (containing pointers) may not be safe! Overlapping members are all serialized.

## Error handling
Success -> bool  
Error message -> interceptable logger
- Asserts are used to confirm correct implementation of the module. A triggered assert indicates a bug.
- Input data errors are flagged by the return boolean indicating the success of the operation. If a procedure indicates failure the reason will be found in the error log.
- To prevent or redirect the TOML module from writing to the error log the user can set a catching or wrapping logger in the context, see examples.

## Memory management & lifetime
Set a context.allocator: `Toml.deserialize(toml_string, My_Struct,, scoped_pool());`  
The lifetime of all returned objects ends when the memory of the allocator is released. In the example case the `scoped_pool` procedure creates a pool allocator that is dropped at the end of the current scope. As such, any allocated objects like strings/arrays/anys/pointers in the returned data may not be used after the scope exit.
- Allocation for returned data are in the context allocator. Instead of free_x() or deinit_x() procedures the user is expected to push an allocator such that all data can be dropped together.
- None of the returned data references allocated data of the input arguments.
- Temporary storage is only used for error messages as some of the intermediate data may be large. If there is a user-friendly way for the caller to replace the temporary allocator let me know, in which case we can just use temp.
- Most temporarily allocated memory in the module is freed in one go by releasing a pool allocator.
- In most cases this means that only the returned data will be left allocated on the context allocator.

## Custom handlers

By default this Toml modules makes several choices like, enums as string, members serialized by their name, no members omitted, etc.
These choices may be fine for the large majority of use-cases but not all. Custom handlers enable the user to modify the serialization/deserialization of types.

Note that these custom handler drive "what" is (de)serialized, they do not help with formatting of the toml.

Serialization can be modified by changing the a custom handler procedure in the context.
```jai
enum_to_value :: (slot: *void, info: *Type_Info) -> done:=true, ok:=false, toml:Value=.{} {
    if info.type != .ENUM return false;
    enum_value := Reflection.get_enum_value(slot, xx info);
    ok, value  := Toml.type_to_value(*enum_value, type_info(s64));
    return true, ok, value;
}

ok, toml := Toml.serialize(
    my_struct
    ,, toml_custom_type_to_value = enum_to_value
);
```

## Testing
`jai ./tests.jai`  
- The module is tested by compiling and running the examples. The command above does that for all examples.

## Implementation

### Two-step (de)serialization
The module supports both Typed as well as Generic data using Toml.Value. To avoid having to maintain 2 implementations the Typed version is implemented by going through the Generic version. As a result there are some extra data copies/allocations as well as limitations like no support for integers > S64_MAX and slightly reduced accuracy for float due to intermediate conversion through float64.

### Type reflection
We only have a run-time reflection based implementation, e.g. pointer and Type_Info based like: `parse :: (slot: *void, info: Type_Info)`. A compile-time reflection based implementation that has the types determined at compile-time like `parse :: (data: *$T)` would have slightly cleaner code and better run-time performance, but it does not support dynamic types like Any. Having multiple implementations, or alternative solutions like requiring the user to poke_name a custom serializer for every possible type contained in the Any are considered undesirable.

### Customization points
Custom handlers have several design goals:
 - Keep the core Toml module implementation clean from complexity.
 - Enable custom serialization of types we do not own (external Modules) as we may not be able to add notes or remove members.
 - The same type should be serializable in different ways defined at the procedure call site, not struct definition.
 - Enable data tweaks during serialization as opposed to full copies of nested structure trees (separate structs for serialization and use within the application).
 - The user should be able to opt-out of the default behavior of handling special types like Toml.Value, Chrono, and SumTypes. A user can opt-out by setting a procedure which is a no-op or any procedure that does not call the default_custom_handler.

In addition to handlers we currently also support making struct members optional through a @TomlOptional note. This means there are 2 ways to do the same thing, it also requires the original Type(_Info) to be modified. It is likely this note will be removed when these kinds of operations are better supported through custom handlers.

The context member `toml_null_value` is introduced as a customization point as it would otherwise be relatively complicated to catch all cases where pointers can occur. toml_null_value can be any kind of Toml.Value, by default it is a string of value `"~null~"`. Deserialization of the value `"~null~"` for a `*string` member can be surprising as it would result into a null pointer instead of a string with value `"~null~"`. The `~`s are added to make it a string that is less likely to occur naturally.
Alternative sentinel values like and empty table `{}` which is the equivalent of a struct without members are not chosen as due to `@TomlOptional` it is also equivalent to a struct with all optional members.

### Lexer
The tokenization/lexer phase completes before the parser starts. As a result memory needs to be allocated to store the tokens. There is no particular reason for this implementation other than that I wanted to experiment with this type of lexer. Unlike traditional lexers the one implemented here does not parse the tokens into literals like int/float/etc it just determines a token starts and ends. It is the responsibility of the parser to interpret the string when it has more context.
