// Times this package. One untimed batch, then batches until the window
// elapses. The sink keeps the call alive.
// Build with clang on the revision before a change, then again after:
//   goose build -o toml-bench bench.goose --cc clang
//   ./toml-bench
// Row names stay fixed. TinyCC (goose bench.goose) is not a timing result.
// ponytail: a fixed window, not a sampled harness. Rows under a microsecond
// move from run to run; lengthen the window before trusting them.

import os;
import parse;

var long_doc: u8[>..] = [];

fn mark(b: u8, ok: bool) -> u64 {
    if !ok { return 0; }
    let v: u64 = b;
    return v + 1;
}

fn time_batch<F>(batch: i64, ms: i64) -> i64, u64 {
    var sink: u64 = 0;
    var k = 0;
    while k < batch {
        sink += F();
        k += 1;
    }
    var n: i64 = 0;
    var dt: i64 = 0;
    let end = clock_ns() + ms * 1000000;
    while true {
        let t0 = clock_ns();
        k = 0;
        while k < batch {
            sink += F();
            k += 1;
        }
        dt += clock_ns() - t0;
        n += batch;
        if clock_ns() >= end { break; }
    }
    return dt / n, sink;
}

fn row<F>(name: u8[:], batch: i64, ms: i64) -> u64 {
    let ns, part = time_batch(batch, ms, F);
    var line: u8[>..] = [];
    format(line, name);
    while line.len < 28 { line.push(' '); }
    format_int(line, ns, 10, 12, ' ');
    format(line, "\n");
    write_stdout(line);
    return part;
}

fn fill_array(n: i64) {
    long_doc.clear();
    long_doc.append("n = [");
    for i in 0..n {
        if i > 0 { long_doc.push(','); }
        long_doc.append(str(i));
    }
    long_doc.push(']');
}

fn parse_one(text: u8[:]) -> u64 {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(text, doc, decoded);
    if err.len != 0 || !root { return 0; }
    let v, ok = parse::int_of(parse::child(root, "a"));
    return mark((v & 255) as! u8, ok);
}

fn short_row() -> u64 { return parse_one("a = 1\n"); }

fn long_row() -> u64 {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(long_doc, doc, decoded);
    if err.len != 0 || !root { return 0; }
    let n = parse::child(root, "n");
    let v, ok = parse::int_of(parse::at(n, 0));
    return mark((v & 255) as! u8, ok && v == 0);
}

fn ready() -> bool {
    if parse_one("a = 1\n") == 0 { return false; }
    fill_array(2000);
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(long_doc, doc, decoded);
    if err.len != 0 || !root { return false; }
    let v, ok = parse::int_of(parse::at(parse::child(root, "n"), 1999));
    return ok && v == 1999;
}

fn ::main() {
    if !ready() { print("bench FAIL"); exit(1); }
    write_stdout("operation                       ns/call\n");
    var sink: u64 = 0;
    sink += row("parse one key", 32, 200, short_row);
    sink += row("parse array 2000", 1, 400, long_row);
    var tail: u8[>..] = [];
    format(tail, "sink ");
    format(tail, sink);
    format(tail, "\n");
    write_stdout(tail);
}
