// The TOML 1.0 list from toml-lang/toml-test (tests/suite/files-toml-1.0.0).
// Invalid documents must fail. Valid documents must match the tagged JSON.

import std;
import os;
import json;
import math;
import toml from "..";
import toml.parse;

namespace toml_test;

// ponytail: 512-byte key path. A grow-only buffer if a fixture nests deeper.
var path: u8[512] = [0; 512];
var path_len: i64 = 0;
var why: u8[64] = [0; 64];
var why_len: i64 = 0;
var failed: i64 = 0;

struct Clock { y: i64, mo: i64, d: i64, h: i64, mi: i64, s: i64, nano: i64, off: i64, ok: bool }

fn push_byte(c: u8) {
    if path_len < 512 { path[path_len] = c; }
    path_len++;
}

fn push_dot_key(key: u8[:]) -> i64 {
    let mark = path_len;
    push_byte('.');
    for i in key.len { push_byte(key[i]); }
    return mark;
}

fn push_index(i: i64) -> i64 {
    let mark = path_len;
    push_byte('[');
    if i == 0 {
        push_byte('0');
    } else {
        var tmp: u8[8] = [0; 8];
        var m = 0;
        var x = i;
        while x > 0 {
            tmp[m] = '0' + (x % 10) as! u8;
            m++;
            x = x / 10;
        }
        while m > 0 {
            m--;
            push_byte(tmp[m]);
        }
    }
    push_byte(']');
    return mark;
}

fn set_why(s: u8[:]) {
    why_len = 0;
    for i in s.len {
        if why_len < 64 {
            why[why_len] = s[i];
            why_len++;
        }
    }
}

fn path_text() -> u8[:] {
    let n = if path_len < 512 { path_len } else { 512 };
    return path[0..n];
}

fn why_text() -> u8[:] { return why[0..why_len]; }

fn i64_eq(v: i64, w: u8[:]) -> bool {
    if v == -9223372036854775808 { return w == "-9223372036854775808"; }
    var buf: u8[20] = [0; 20];
    var n = 0;
    var neg = v < 0;
    var x = if neg { -v } else { v };
    if x == 0 {
        buf[0] = '0';
        n = 1;
    } else {
        var tmp: u8[20] = [0; 20];
        var m = 0;
        while x > 0 {
            tmp[m] = '0' + (x % 10) as! u8;
            m++;
            x = x / 10;
        }
        if neg {
            buf[n] = '-';
            n++;
        }
        while m > 0 {
            m--;
            buf[n] = tmp[m];
            n++;
        }
    }
    return buf[0..n] == w;
}

fn word_nan(w: u8[:]) -> bool {
    var s = w;
    if s.len > 0 && (s[0] == '+' || s[0] == '-') { s = s[1..]; }
    return s == "nan";
}

fn word_inf(w: u8[:]) -> bool {
    var s = w;
    if s.len > 0 && (s[0] == '+' || s[0] == '-') { s = s[1..]; }
    return s == "inf";
}

fn same_float(v: f64, w: u8[:]) -> bool {
    if word_nan(w) { return is_nan(v); }
    if word_inf(w) {
        if !is_inf(v) { return false; }
        if w.len > 0 && w[0] == '-' { return v < 0.0; }
        return v > 0.0;
    }
    let e, ok = parse_flt(w);
    return ok && e == v;
}

fn take_digits(s: u8[:], i: i64&, n: i64) -> i64, bool {
    var v = 0;
    for k in 0..n {
        if i >= s.len || s[i] < '0' || s[i] > '9' { return 0, false; }
        v = v * 10 + (s[i] - '0');
        i++;
    }
    return v, true;
}

fn read_hms(s: u8[:], i: i64&, c: Clock&) -> bool {
    let h, hok = take_digits(s, i, 2);
    if !hok || i >= s.len || s[i] != ':' { return false; }
    i++;
    let mi, mok = take_digits(s, i, 2);
    if !mok || i >= s.len || s[i] != ':' { return false; }
    i++;
    let sec, sok = take_digits(s, i, 2);
    if !sok { return false; }
    c.h = h;
    c.mi = mi;
    c.s = sec;
    if i < s.len && s[i] == '.' {
        i++;
        var nano = 0;
        var scale = 100000000;
        var any = false;
        while i < s.len && s[i] >= '0' && s[i] <= '9' {
            any = true;
            if scale > 0 {
                nano += (s[i] - '0') * scale;
                scale = scale / 10;
            }
            i++;
        }
        if !any { return false; }
        c.nano = nano;
    }
    return true;
}

fn read_off(s: u8[:], i: i64&, c: Clock&) -> bool {
    if i >= s.len { return true; }
    let ch = s[i];
    if ch == 'Z' || ch == 'z' {
        i++;
        return true;
    }
    if ch != '+' && ch != '-' { return true; }
    let sign = if ch == '-' { -1 } else { 1 };
    i++;
    let h, hok = take_digits(s, i, 2);
    if !hok || i >= s.len || s[i] != ':' { return false; }
    i++;
    let m, mok = take_digits(s, i, 2);
    if !mok { return false; }
    c.off = sign * (h * 60 + m);
    return true;
}

fn read_clock(s: u8[:]) -> Clock {
    var c = Clock { y: 0, mo: 0, d: 0, h: 0, mi: 0, s: 0, nano: 0, off: 0, ok: false };
    var i = 0;
    if s.len >= 5 && s[4] == '-' {
        let y, yok = take_digits(s, i, 4);
        if !yok || i >= s.len || s[i] != '-' { return c; }
        i++;
        let mo, mok = take_digits(s, i, 2);
        if !mok || i >= s.len || s[i] != '-' { return c; }
        i++;
        let d, dok = take_digits(s, i, 2);
        if !dok { return c; }
        c.y = y;
        c.mo = mo;
        c.d = d;
        if i < s.len && (s[i] == 'T' || s[i] == 't' || s[i] == ' ') {
            i++;
            if !read_hms(s, i, c) { return c; }
            if !read_off(s, i, c) { return c; }
        }
    } else if !read_hms(s, i, c) {
        return c;
    }
    c.ok = i == s.len;
    return c;
}

fn clock_eq(a: u8[:], b: u8[:]) -> bool {
    let ca = read_clock(a);
    let cb = read_clock(b);
    return ca.ok && cb.ok && ca.y == cb.y && ca.mo == cb.mo && ca.d == cb.d && ca.h == cb.h && ca.mi == cb.mi && ca.s == cb.s && ca.nano == cb.nano && ca.off == cb.off;
}

fn tagged(n: json::Node?) -> bool {
    guard n else { return false; }
    match n.val {
        Obj o => { if o.count != 2 { return false; } },
        _ => { return false; },
    }
    let t = json::member(n, "type");
    guard t else { return false; }
    match t.val {
        Str => {},
        _ => { return false; },
    }
    guard json::member(n, "value") else { return false; }
    return true;
}

recursive fn same_value(have: parse::Node?, want: json::Node?) -> bool {
    let typ, tok = json::as_string(json::member(want, "type"));
    let val = json::member(want, "value");
    if !tok { set_why("type"); return false; }
    if typ == "string" {
        let s, ok = parse::string_of(have);
        let w, wok = json::as_string(val);
        if !ok || !wok || s != w { set_why("string"); return false; }
        return true;
    }
    if typ == "integer" {
        let n, ok = parse::int_of(have);
        let w, wok = json::as_string(val);
        if !ok || !wok || !i64_eq(n, w) { set_why("integer"); return false; }
        return true;
    }
    if typ == "float" {
        let n, ok = parse::float_of(have);
        let w, wok = json::as_string(val);
        if !ok || !wok || !same_float(n, w) { set_why("float"); return false; }
        return true;
    }
    if typ == "bool" {
        let n, ok = parse::bool_of(have);
        let w, wok = json::as_string(val);
        if !ok || !wok || (w != "true" && w != "false") || n != (w == "true") { set_why("bool"); return false; }
        return true;
    }
    if typ == "datetime" || typ == "datetime-local" || typ == "date-local" || typ == "time-local" {
        let when, s, ok = parse::time_of(have);
        let w, wok = json::as_string(val);
        if !ok || !wok { set_why("time"); return false; }
        if typ == "datetime" && when != parse::When.Offset { set_why("datetime"); return false; }
        if typ == "datetime-local" && when != parse::When.LocalDateTime { set_why("datetime-local"); return false; }
        if typ == "date-local" && when != parse::When.LocalDate { set_why("date"); return false; }
        if typ == "time-local" && when != parse::When.LocalTime { set_why("time-local"); return false; }
        if !clock_eq(s, w) { set_why("clock"); return false; }
        return true;
    }
    set_why("kind");
    return false;
}

recursive fn same_array(have: parse::Node?, want: json::Node?) -> bool {
    guard have else { set_why("array"); return false; }
    guard want else { set_why("json array"); return false; }
    var hn = 0;
    var wn = 0;
    match have.val {
        Array a => { hn = a.count; },
        _ => { set_why("array"); return false; },
    }
    match want.val {
        Arr a => { wn = a.count; },
        _ => { set_why("json array"); return false; },
    }
    if hn != wn { set_why("array length"); return false; }
    var i = 0;
    var hc = have.first;
    var wc = want.first;
    while hc {
        guard wc else { set_why("array short"); return false; }
        let mark = push_index(i);
        if !same_any(hc, wc) { return false; }
        path_len = mark;
        i++;
        hc .= hc.next;
        wc .= wc.next;
    }
    return true;
}

recursive fn same_table(have: parse::Node?, want: json::Node?) -> bool {
    guard have else { set_why("table"); return false; }
    guard want else { set_why("json table"); return false; }
    var hn = 0;
    var wn = 0;
    match have.val {
        Table t => { hn = t.count; },
        _ => { set_why("table"); return false; },
    }
    match want.val {
        Obj o => { wn = o.count; },
        _ => { set_why("json table"); return false; },
    }
    if hn != wn { set_why("keys"); return false; }
    var c = want.first;
    while c {
        let mark = push_dot_key(c.key);
        let got = parse::child(have, c.key);
        if !got { set_why("missing"); return false; }
        if !same_any(got, c) { return false; }
        path_len = mark;
        c .= c.next;
    }
    return true;
}

recursive fn same_any(have: parse::Node?, want: json::Node?) -> bool {
    guard want else { set_why("json"); return false; }
    match want.val {
        Arr => { return same_array(have, want); },
        _ => {},
    }
    if tagged(want) { return same_value(have, want); }
    return same_table(have, want);
}

fn check_invalid(file: u8[:]) {
    var text: u8[>..] = [];
    if !read_file(file, text) {
        print("cannot read ", file);
        failed++;
        return;
    }
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(text, doc, decoded);
    if err.len == 0 || root {
        print(file);
        failed++;
    }
}

fn check_valid(file: u8[:]) {
    var text: u8[>..] = [];
    if !read_file(file, text) {
        print("cannot read ", file);
        failed++;
        return;
    }
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(text, doc, decoded);
    if err.len != 0 || !root {
        print(file);
        print(err);
        failed++;
        return;
    }
    let jpath = str(file[..file.len - 5], ".json");
    var jtext: u8[>..] = [];
    if !read_file(jpath, jtext) {
        print("cannot read ", jpath);
        failed++;
        return;
    }
    var jdoc: json::Node[>..] = [];
    var jdec: u8[>..] = [];
    let jroot, jerr = json::parse(jtext, jdoc, jdec);
    if jerr.len != 0 || !jroot {
        print(jpath);
        print(jerr);
        failed++;
        return;
    }
    path_len = 0;
    why_len = 0;
    if !same_table(root, jroot) {
        print(str(file, " ", path_text(), " ", why_text()));
        failed++;
    }
}

fn walk(root: u8[:], invalid: bool) {
    var dirs: u8[>..] = [];
    for i in root.len { dirs.push(root[i]); }
    dirs.push('\n');
    var at = 0;
    while at < dirs.len {
        let from = at;
        while dirs[at] != '\n' { at++; }
        let dir = str(dirs[from..at]);
        at++;
        var names: u8[>..] = [];
        if !list_dir(dir, names) {
            print("cannot list ", dir);
            failed++;
            continue;
        }
        var i = 0;
        while i < names.len {
            let start = i;
            while i < names.len && names[i] != '\n' { i++; }
            let name = names[start..i];
            if i < names.len { i++; }
            if name.len == 0 { continue; }
            let path = str(dir, name);
            if is_dir(path) {
                for k in path.len { dirs.push(path[k]); }
                dirs.push('/');
                dirs.push('\n');
                continue;
            }
            if ends_with(name, ".toml") {
                if invalid { check_invalid(path); }
                else { check_valid(path); }
            }
        }
    }
}

fn run() {
    let base = resource_dir();
    walk(str(base, "suite/invalid/"), true);
    walk(str(base, "suite/valid/"), false);
    if failed != 0 {
        print(failed, " fixture failures");
        exit(1);
    }
}

fn ::main() {
    toml_test::run();
    print("toml ok");
}
