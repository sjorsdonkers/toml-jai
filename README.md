# TOML-jai

A module for `TOML v1.0.0` support. It provides functionality to read/write TOML files and convert them directly to/from Jai data structures.

- Full TOML v1.0.0 support.
- All run-time data types are supported as their native type including reference types (`pointer`, `array`, `any`), with the exception of untagged `unions`.
- Generic data is supported through the [Toml.Value](src/data.jai) struct.
- Dates/times are supported types provided in [src/datetime.jai](src/datetime.jai) (until Jai has native types).
- Safe sum-types with `@UnionTag` notes to indicate the tag member corresponding to a union.
- There is currently no way to provide an alternative (de)serialization procedures for a user-defined type (e.g. Jai's Tagged_Union would serialize as an array of u8 numbers and the contents of the Type_Info)

## Deserialize
- Read TOML directly into any (nested) struct.
- Any field not in the TOML is default initialized. Any superfluous fields in the TOML are ignored.
- Compile-time constants are ignored and not compared.
- If the parser understands the input it will accept it even if it is officially invalid according to the standard. This may in the future change to be more strict.

## Serialize
- Write any (nested) struct or Toml.Value to TOML string.
- Null pointers/null Anys are skipped, null pointers/null Anys in arrays will error.
- Compile-time constants are skipped.

## Error handling
- Asserts are used to confirm correct implementation of the module. If a triggered assert indicated a bug.
- Input data errors are flagged by the return boolean indicating the success of the operation. If a procedure indicates failure the reason will be found in the error log.
- To prevent or redirect the TOML module from writing to the error log the user can set a catching or wrapping logger in the context.

## Memory management
- Returned data may have data allocated on the context allocator. Instead of free_x() procedures the user is expected to push an allocator such that all data can be dropped together.
- Temporary storage is only used for serializing floats and errors.
- All memory temporarily allocated in the module is freed together from a pool allocator.
- In most cases this means that only the returned data will be left allocated on the context allocator.


## Testing
The module is tested by compiling and running the examples. All examples can be compiled and run by `jai ./tests.jai`
