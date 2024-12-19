# TOML-jai

A module for `TOML v1.0.0` support. It provides functionality to parse TOML files and deserialize directly them into Jai data structures.

- Full TOML v1.0.0 support.
- All data types are supported as their native type including reference types (`pointer`, `array`, `any`).
- Generic data is supported through the Toml.Value struct.
- Dates/times are deserialized as one of the types provided in Toml/datetime.jai (until Jai has native types).
- There are currently no way to provide an alternative serialization procedures for a user--defined type (e.g. Jai's Tagged_Union would serialize as a byte array)

## Deserialize
- Parse TOML directly into any (nested) struct.
- Safe sum-types with `@UnionTag` notes to indicate the tag member corresponding to a union.
- Any field not in the TOML is default initialized. Any superfluous fields in the TOML are ignored.
- Compile-time constants are ignored and not compared.
- If the parser understands the input it will accept it even if it is officially invalid according to the standard.
- WIP Failure to parse the input will currently result in a program `exit()`.

## Serialize
- Write any (nested) struct or Toml.Value to TOML string.
- Exception: Unions without `@UnionTag` note are not supported.
- Null pointers/Anys are not written, null pointers/Anys in arrays will error.
- Compile-time constants are not written.
- WIP Failure to serialize the input will currently result in a program `exit()`.
