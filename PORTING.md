# What this package does not port

This package reads [TOML 1.0](https://toml.io/en/v1.0.0). `parse` fills a tree of nodes. `child`, `at`, and the `*_of` functions read one field. The caller keeps the node pool and the escape buffer alive for as long as it holds a node.

It does not port a writer. Nothing here turns a tree back into TOML text.

It does not port serde. There is no `Serialize` or `Deserialize`, and no function that fills an arbitrary Goose struct. You read each field yourself. Goose has no derives, and this package does not add a substitute.

It does not accept the TOML 1.1 relaxations. A newline inside an inline table is an error, and so is a trailing comma in an inline table. Arrays may still span lines and may still end with a comma.

An integer that does not fit in `i64` is an error. `+0` and `-0` are the integer 0. Floats are IEEE binary64. A long mantissa can be off by one unit in the last place, which is the same limit as `parse_flt`. `+nan` and `-nan` are a NaN; the spec leaves the exact bits to the implementation. `+0.0` and `-0.0` keep their sign. `+inf` and `-inf` are the IEEE infinities.

Newlines inside multiline strings stay as they were written. A date, time, or offset date-time is the source text plus which of the four forms it was. The calendar rejects a day the month does not have, including 29 February outside a leap year. Second 60 is allowed.

Strings with no escapes are slices of the source. Escapes are appended to the buffer you pass. A node from `parse` is only valid while that pool and that buffer are.
