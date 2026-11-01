<p align="center">
  <img src="logo.png" alt="A goose holding a TOML page" width="220">
</p>

<h1 align="center">goose-toml</h1>

<p align="center">
  TOML for <a href="https://github.com/aardappel/goose">Goose</a><br>
  <strong>0.2</strong> · <a href="LICENSE">Apache-2.0</a>
</p>

Reads [TOML 1.0](https://toml.io/en/v1.0.0). `parse` fills a tree you own. You then read each field with `child`, `at`, and the `*_of` functions. A bad document comes back as a message.

## Example

```goose
import toml from "../toml";
import toml.parse;

fn main() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse("name = \"goose\"\n", doc, decoded);
    let name, ok = parse::string_of(parse::child(root, "name"));
    if err.len == 0 && ok { print(name); }
}
```

`toml.goose` is the package entry. It does not load the parser. `import toml.parse` does. Keep `doc` and `decoded` alive while you hold a node. Strings with no escapes are slices of the source. Escapes are appended to `decoded`.

## Check

Install the Goose compiler, then from this directory:

```sh
goose tests/self_check.goose
```

A good run prints `toml ok`. That includes the TOML 1.0 fixtures from [toml-test](https://github.com/toml-lang/toml-test), copied under `tests/suite`.

## Modules

| Module | What it does |
| --- | --- |
| `parse` | Reads one TOML 1.0 document into a tree of nodes |

## Good to know

Integers are `i64`. A value that does not fit is an error. Floats are IEEE binary64, including the infinities and NaN. A date or time is the source text plus which of the four forms it was: offset, local date-time, local date, or local time.

There is no writer. `PORTING.md` lists what this package leaves out, including serde and the TOML 1.1 inline-table rules.

## License

Apache-2.0. Free and open to everyone. The terms are in [LICENSE](LICENSE).
