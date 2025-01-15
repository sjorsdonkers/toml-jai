# TOML-jai

A module for `TOML v1.0.0` support. It provides functionality to read/write TOML files and convert them directly to/from Jai data structures.

- Full TOML v1.0.0 support.
- All run-time data types are supported as their native type including reference types (`pointer`, `array`, `any`), with the exception of untagged `unions`.
- Generic data is supported through the [Toml.Value](src/data.jai) struct.
- Dates/times are supported types provided in [src/datetime.jai](src/datetime.jai) (until Jai has native types).
- Safe sum-types with `@UnionTag` notes to indicate the tag member corresponding to a union.
- There is currently no way to provide an alternative (de)serialization procedures for a user-defined type (e.g. Jai's Tagged_Union would serialize as an array of u8 numbers and the contents of the Type_Info)

Latest confirmed compatible Jai Version: beta 0.2.008, built on 14 January 2025.

## Deserialize
`ok, my_struct := Toml.deserialize(toml_string, My_Struct);`
- Read TOML directly into any (nested) struct or generic `Toml.Value`.
- Any field not in the TOML is default initialized. Any superfluous fields in the TOML are ignored.
- Compile-time constants are ignored and not compared.
- If the parser understands the input it will accept it even if it is officially invalid according to the standard. This may in the future change to be more strict.

## Serialize
`ok, toml_string := Toml.serialize(my_struct);`
- Write any (nested) struct or `Toml.Value` to TOML string.
- Null pointers/null Anys are skipped, null pointers/null Anys in arrays will error.
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

## Testing
`jai ./tests.jai`  
- The module is tested by compiling and running the examples. The command above does that for all examples.

## Implementation

### Two-step (de)serialization
The module supports both Typed as well as Generic data using Toml.Value. To avoid having to maintain 2 implementations the Typed version is implemented by going through the Generic version. As a result there are some extra data copies/allocations as well as limitations like no support for integers > S64_MAX and slightly reduced accuracy for float due to intermediate conversion through float64.

### Type reflection
We only have a run-time reflection based implementation, e.g. pointer and Type_Info based like: `parse :: (slot: *void, info: Type_Info)`. A compile-time reflection based implementation that has the types determined at compile-time like `parse :: (data: *$T)` would have slightly cleaner code and better run-time performance, but it does not support dynamic types like Any. Having multiple implementations, or alternative solutions like requiring the user to poke_name a custom serializer for every possible type contained in the Any are considered undesirable.

### [planned] Customization points
A user may want to modify how a struct is serialized for example: omit members, rename members or create a specific toml structure. For various use cases we may implement specific solutions like notes on members that are required/optional, or their serialization name. For more complex cases we may allow the user to provide a procedure that converts A->B such that whenever an A occurs it is serialized as a B (note that B could be Toml.Value). Likely such a conversion procedures would come in pairs for serialization A->B and deserialization B->A.

### Lexer
The tokenization/lexer phase completes before the parser starts. As a result memory needs to be allocated to store the tokens. There is no particular reason for this implementation other than that I wanted to experiment with this type of lexer. Unlike traditional lexers the one implemented here does not parse the tokens into literals like int/float/etc it just determines a token starts and ends. It is the responsibility of the parser to interpret the string when it has more context.
