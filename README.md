# TOML-jai

A module for `TOML v1.0.0` support. It provides functionality to parse TOML files and deserialize directly them into Jai data structures.

- Full TOML v1.0.0 support.
- Dates/times are deserialized as one of the types provided in Toml/datetime.jai (until Jai has native types).
## Deserialize
- Parse TOML directly into any (nested) struct, including reference types (`pointer`, `array`, `any`), or use Toml.Value for generic data.
- Safe sum-types with `@UnionTag` notes to indicate the tag member corresponding to a union.
- Any field not in the TOML is default initialized. Any superfluous fields in the TOML are ignored.
- If the parser understands the input it will accept it even if it is officially invalid according to the standard.
- WIP Failure to parse the input will currently result in a program `exit()`.

## Serialize
- Write any (nested) struct or Toml.Value to TOML string.
- Exception: Unions without `@UnionTag` note are not supported.
- Null pointers/Anys are not written, everything else is.
- WIP Failure to serialize the input will currently result in a program `exit()`.
