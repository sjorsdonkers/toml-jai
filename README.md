# TOML-jai

A module for `TOML v1.0.0` support. It provides functionality to parse TOML files and deserialize directly them into Jai data structures.

## Deserialize
- Full TOML v1.0.0 support.
- Parse TOML directly into any (nested) struct, including reference types (`pointer`, `array`, `any`), or use Toml.Value for generic data.
- Any field not in the TOML is default initialized. Any superfluous fields in the TOML are ignored.
- Dates/times are deserialized as string, or as provided types in Toml/datetime.jai (until Jai has native types).
- If the parser understands the input it will accept it even if it is officially invalid according to the standard.
- WIP Failure to parse the input will currently result in a program `exit()`.
