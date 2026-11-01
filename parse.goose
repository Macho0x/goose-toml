// TOML 1.0. parse fills doc, and appends escaped strings to decoded.
// Plain strings and keys are slices of text. A bad document is null and
// "toml: <reason> at byte <n>". An integer that does not fit in i64 is an
// error. Keep both arrays alive while a node is in use. There is no writer.
//
// child and at walk one level. string_of, int_of, float_of, bool_of, and
// time_of read a leaf.

import std;

namespace parse;

enum TableKind { Implicit, Dotted, Defined, Inline }

enum Items { Values, Tables }

enum When { Offset, LocalDateTime, LocalDate, LocalTime }

enum Value {
    String { s: const u8[:] },
    Int { v: i64 },
    Float { v: f64 },
    Bool { v: bool },
    Time { when: When, s: const u8[:] },
    Array { count: i64, items: Items },
    Table { count: i64, kind: TableKind },
}

struct Node { next: Node&<u32>?, first: Node&<u32>?, key: const u8[:], val: Value }

fn hex_val(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    return -1;
}

fn bare(c: u8) -> bool {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

fn digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

fn month_days(year: i64, month: i64) -> i64 {
    if month == 2 {
        if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) { return 29; }
        return 28;
    }
    if month == 4 || month == 6 || month == 9 || month == 11 { return 30; }
    return 31;
}

// -1 when s is UTF-8. Otherwise the byte where it stops being UTF-8.
fn utf8_bad(s: u8[:]) -> i64 {
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c < 0x80 {
            i++;
            continue;
        }
        var need = 0;
        var min = 0;
        var cp = 0;
        if c >= 0xC2 && c <= 0xDF {
            need = 1;
            min = 0x80;
            cp = c & 0x1F;
        } else if c >= 0xE0 && c <= 0xEF {
            need = 2;
            min = 0x800;
            cp = c & 0x0F;
        } else if c >= 0xF0 && c <= 0xF4 {
            need = 3;
            min = 0x10000;
            cp = c & 0x07;
        } else {
            return i;
        }
        if i + need >= s.len { return i; }
        for k in 0..need {
            let d = s[i + 1 + k];
            if d < 0x80 || d > 0xBF { return i + 1 + k; }
            cp = cp * 64 + (d & 0x3F);
        }
        if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return i; }
        i += need + 1;
    }
    return -1;
}

fn ieee_inf(neg: bool) -> f64 {
    var v = 1e308 * 1e10;
    if neg { return -v; }
    return v;
}

fn ieee_nan() -> f64 {
    let v = ieee_inf(false);
    return v - v;
}

fn find(n: Node&, key: u8[:]) -> Node? {
    var c = n.first;
    while c {
        if c.key == key { return c; }
        c .= c.next;
    }
    return null;
}

fn child(n: Node?, key: u8[:]) -> Node? {
    guard n else { return null; }
    match n.val {
        Table => {},
        _ => { return null; },
    }
    return find(n, key);
}

fn at(n: Node?, i: i64) -> Node? {
    guard n else { return null; }
    match n.val {
        Array => {},
        _ => { return null; },
    }
    if i < 0 { return null; }
    var c = n.first;
    var k = 0;
    while c {
        if k == i { return c; }
        k++;
        c .= c.next;
    }
    return null;
}

fn string_of(n: Node?) -> const u8[:], bool {
    guard n else { return "", false; }
    match n.val {
        String s => { return s.s, true; },
        _ => { return "", false; },
    }
}

fn int_of(n: Node?) -> i64, bool {
    guard n else { return 0, false; }
    match n.val {
        Int v => { return v.v, true; },
        _ => { return 0, false; },
    }
}

fn float_of(n: Node?) -> f64, bool {
    guard n else { return 0.0, false; }
    match n.val {
        Float v => { return v.v, true; },
        _ => { return 0.0, false; },
    }
}

fn bool_of(n: Node?) -> bool, bool {
    guard n else { return false, false; }
    match n.val {
        Bool v => { return v.v, true; },
        _ => { return false, false; },
    }
}

fn time_of(n: Node?) -> When, const u8[:], bool {
    guard n else { return When.LocalDate, "", false; }
    match n.val {
        Time t => { return t.when, t.s, true; },
        _ => { return When.LocalDate, "", false; },
    }
}

fn bail(at: i64, what: const u8[:]) {
    return null, str("toml: ", what, " at byte ", at) from parse;
}

fn eat_newline(text: u8[:], pos: i64&) -> bool {
    if pos >= text.len { return false; }
    if text[pos] == '\n' {
        pos++;
        return true;
    }
    if text[pos] == '\r' && pos + 1 < text.len && text[pos + 1] == '\n' {
        pos += 2;
        return true;
    }
    return false;
}

// span is arrays, where a newline is whitespace. A comment never eats the newline.
fn skip_ws(text: u8[:], pos: i64&, span: bool) {
    loop {
        if pos >= text.len { return; }
        let c = text[pos];
        if c == ' ' || c == '\t' {
            pos++;
            continue;
        }
        if span && (c == '\n' || c == '\r') {
            if !eat_newline(text, pos) { bail(pos, "control character"); }
            continue;
        }
        if c == '#' {
            pos++;
            while pos < text.len && text[pos] != '\n' && text[pos] != '\r' {
                let d = text[pos];
                if d == 0x7F || (d < 0x20 && d != '\t') { bail(pos, "control character"); }
                pos++;
            }
            continue;
        }
        return;
    }
}

fn finish_line(text: u8[:], pos: i64&) {
    skip_ws(text, pos, false);
    if pos >= text.len { return; }
    if eat_newline(text, pos) { return; }
    bail(pos, "expected newline");
}

fn skip_gap(text: u8[:], pos: i64&) {
    loop {
        skip_ws(text, pos, false);
        if !eat_newline(text, pos) { return; }
    }
}

fn bad_control(c: u8, multi: bool) -> bool {
    if c == 0x7F { return true; }
    if c >= 0x20 { return false; }
    if c == '\t' { return false; }
    if multi && (c == '\n' || c == '\r') { return false; }
    return true;
}

fn read_string(text: u8[:], pos: i64&, decoded: u8[>..]&) -> const u8[:] {
    // i is the first whitespace byte after a backslash. -1 when the backslash
    // is not a line-ending trim.
    fn line_break(i: i64, limit: i64) -> i64 {
        var j = i;
        var saw = false;
        while j < limit {
            let c = text[j];
            if c != ' ' && c != '\t' && c != '\n' && c != '\r' { break; }
            if c == '\n' || c == '\r' { saw = true; }
            if c == '\r' && j + 1 < limit && text[j + 1] == '\n' { j += 2; }
            else { j++; }
        }
        if !saw { return -1; }
        return j;
    }

    fn after_escape(i: i64, limit: i64, multi: bool) -> i64 {
        var j = i + 1;
        if j >= limit { bail(i, "bad escape"); }
        let e = text[j];
        if e == 'b' || e == 't' || e == 'n' || e == 'f' || e == 'r' || e == '"' || e == '\\' { return j + 1; }
        if e == 'u' || e == 'U' {
            let n = if e == 'u' { 4 } else { 8 };
            j++;
            var cp = 0;
            for k in 0..n {
                if j + k >= limit { bail(i, "bad escape"); }
                let h = hex_val(text[j + k]);
                if h < 0 { bail(i, "bad escape"); }
                cp = cp * 16 + h;
            }
            if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { bail(i, "bad escape"); }
            return j + n;
        }
        if multi && (e == ' ' || e == '\t' || e == '\n' || e == '\r') {
            let npos = line_break(j, limit);
            if npos < 0 { bail(i, "bad escape"); }
            return npos;
        }
        bail(i, "bad escape");
    }

    fn emit_escape(i: i64, limit: i64) -> i64 {
        var j = i + 1;
        if j >= limit { bail(i, "bad escape"); }
        let e = text[j];
        if e == 'b' { decoded.push(0x08); return j + 1; }
        if e == 't' { decoded.push('\t'); return j + 1; }
        if e == 'n' { decoded.push('\n'); return j + 1; }
        if e == 'f' { decoded.push(0x0C); return j + 1; }
        if e == 'r' { decoded.push('\r'); return j + 1; }
        if e == '"' { decoded.push('"'); return j + 1; }
        if e == '\\' { decoded.push('\\'); return j + 1; }
        if e == 'u' || e == 'U' {
            let n = if e == 'u' { 4 } else { 8 };
            j++;
            var cp = 0;
            for k in 0..n {
                if j + k >= limit { bail(i, "bad escape"); }
                let h = hex_val(text[j + k]);
                if h < 0 { bail(i, "bad escape"); }
                cp = cp * 16 + h;
            }
            if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { bail(i, "bad escape"); }
            push_utf8(decoded, cp);
            return j + n;
        }
        if e == ' ' || e == '\t' || e == '\n' || e == '\r' {
            let npos = line_break(j, limit);
            if npos < 0 { bail(i, "bad escape"); }
            return npos;
        }
        bail(i, "bad escape");
    }

    fn decode_basic(start: i64, end: i64) -> const u8[:] {
        let mark = decoded.len;
        var i = start;
        while i < end {
            if text[i] == '\\' {
                i = emit_escape(i, end);
                continue;
            }
            decoded.push(text[i]);
            i++;
        }
        return decoded[mark..];
    }

    fn take_basic(start: i64, multi: bool) -> const u8[:] {
        var i = start;
        var escaped = false;
        while i < text.len {
            let c = text[i];
            if c == '\\' {
                escaped = true;
                i = after_escape(i, text.len, multi);
                continue;
            }
            if c == '"' {
                var n = 0;
                while i + n < text.len && text[i + n] == '"' { n++; }
                if !multi {
                    pos = i + 1;
                    if escaped { return decode_basic(start, i); }
                    return text[start..i];
                }
                // One or two quotes may sit against the closing three.
                if n >= 3 {
                    var end = i;
                    var eat = 3;
                    if n <= 5 {
                        end = i + n - 3;
                        eat = n;
                    }
                    pos = i + eat;
                    if escaped { return decode_basic(start, end); }
                    return text[start..end];
                }
                i += n;
                continue;
            }
            if bad_control(c, multi) { bail(i, "control character"); }
            i++;
        }
        bail(i, "unclosed string");
    }

    fn take_literal(start: i64, multi: bool) -> const u8[:] {
        var i = start;
        while i < text.len {
            let c = text[i];
            if c == '\'' {
                var n = 0;
                while i + n < text.len && text[i + n] == '\'' { n++; }
                if !multi {
                    pos = i + 1;
                    return text[start..i];
                }
                if n >= 3 {
                    var end = i;
                    var eat = 3;
                    if n <= 5 {
                        end = i + n - 3;
                        eat = n;
                    }
                    pos = i + eat;
                    return text[start..end];
                }
                i += n;
                continue;
            }
            if bad_control(c, multi) { bail(i, "control character"); }
            i++;
        }
        bail(i, "unclosed string");
    }

    if pos >= text.len { bail(pos, "unclosed string"); }
    let quote = text[pos];
    pos++;
    var multi = false;
    if pos + 1 < text.len && text[pos] == quote && text[pos + 1] == quote {
        multi = true;
        pos += 2;
        if pos < text.len && text[pos] == '\r' {
            pos++;
            if pos < text.len && text[pos] == '\n' { pos++; }
        } else if pos < text.len && text[pos] == '\n' {
            pos++;
        }
    }
    let start = pos;
    if quote == '\'' { return take_literal(start, multi); }
    return take_basic(start, multi);
}

fn read_key(text: u8[:], pos: i64&, decoded: u8[>..]&) -> const u8[:] {
    skip_ws(text, pos, false);
    if pos >= text.len { bail(pos, "expected a key"); }
    let c = text[pos];
    if c == '"' || c == '\'' {
        if pos + 2 < text.len && text[pos + 1] == c && text[pos + 2] == c { bail(pos, "multiline key"); }
        return read_string(text, pos, decoded);
    }
    if bare(c) {
        let start = pos;
        while pos < text.len && bare(text[pos]) { pos++; }
        return text[start..pos];
    }
    bail(pos, "expected a key");
}

fn read_value(text: u8[:], pos: i64&, decoded: u8[>..]&) -> Value {
    fn bound() {
        if pos < text.len && bare(text[pos]) { bail(pos, "bad value"); }
    }

    fn ahead(n: i64, sep: u8) -> bool {
        if pos + n >= text.len { return false; }
        for k in 0..n {
            if !digit(text[pos + k]) { return false; }
        }
        return text[pos + n] == sep;
    }

    fn read_n(n: i64, what: const u8[:]) -> i64 {
        var v = 0;
        for k in 0..n {
            if pos >= text.len || !digit(text[pos]) { bail(pos, what); }
            v = v * 10 + (text[pos] - '0');
            pos++;
        }
        return v;
    }

    fn need(c: u8, what: const u8[:]) {
        if pos >= text.len || text[pos] != c { bail(pos, what); }
        pos++;
    }

    fn read_hms() {
        let hh = read_n(2, "bad time");
        need(':', "bad time");
        let mm = read_n(2, "bad time");
        need(':', "bad time");
        let ss = read_n(2, "bad time");
        if hh > 23 || mm > 59 || ss > 60 { bail(pos, "bad time"); }
        if pos < text.len && text[pos] == '.' {
            pos++;
            var n = 0;
            while pos < text.len && digit(text[pos]) {
                pos++;
                n++;
            }
            if n == 0 { bail(pos, "bad time"); }
        }
    }

    fn take_date(begin: i64) -> Value {
        let year = read_n(4, "bad date");
        need('-', "bad date");
        let month = read_n(2, "bad date");
        need('-', "bad date");
        let day = read_n(2, "bad date");
        if month < 1 || month > 12 || day < 1 || day > month_days(year, month) { bail(pos, "bad date"); }
        var timed = false;
        if pos < text.len && (text[pos] == 'T' || text[pos] == 't') {
            timed = true;
            pos++;
        } else if pos + 1 < text.len && text[pos] == ' ' && digit(text[pos + 1]) {
            timed = true;
            pos++;
        }
        if !timed {
            bound();
            return Value.Time { when: When.LocalDate, s: text[begin..pos] };
        }
        read_hms();
        if pos < text.len && (text[pos] == 'Z' || text[pos] == 'z' || text[pos] == '+' || text[pos] == '-') {
            if text[pos] == 'Z' || text[pos] == 'z' {
                pos++;
            } else {
                pos++;
                let hh = read_n(2, "bad date");
                need(':', "bad date");
                let mm = read_n(2, "bad date");
                if hh > 23 || mm > 59 { bail(pos, "bad date"); }
            }
            bound();
            return Value.Time { when: When.Offset, s: text[begin..pos] };
        }
        bound();
        return Value.Time { when: When.LocalDateTime, s: text[begin..pos] };
    }

    fn take_time(begin: i64) -> Value {
        read_hms();
        bound();
        return Value.Time { when: When.LocalTime, s: text[begin..pos] };
    }

    fn strip(from: i64, to: i64) -> const u8[:] {
        var i = from;
        while i < to {
            if text[i] == '_' {
                let mark = decoded.len;
                var j = from;
                while j < to {
                    if text[j] != '_' { decoded.push(text[j]); }
                    j++;
                }
                return decoded[mark..];
            }
            i++;
        }
        return text[from..to];
    }

    fn eat_digits(what: const u8[:]) {
        if pos >= text.len || !digit(text[pos]) { bail(pos, what); }
        while pos < text.len && digit(text[pos]) {
            pos++;
            if pos < text.len && text[pos] == '_' {
                pos++;
                if pos >= text.len || !digit(text[pos]) { bail(pos, "bad underscore"); }
            }
        }
    }

    fn take_radix() -> Value {
        let kind = text[pos + 1];
        var base = 16;
        if kind == 'o' { base = 8; }
        else if kind == 'b' { base = 2; }
        pos += 2;
        let start = pos;
        var prev = false;
        var any = false;
        while pos < text.len {
            let c = text[pos];
            if c == '_' {
                if !prev { bail(pos, "bad integer"); }
                pos++;
                prev = false;
                continue;
            }
            let h = hex_val(c);
            if h < 0 || h >= base { break; }
            prev = true;
            any = true;
            pos++;
        }
        if !any || !prev { bail(pos, "bad integer"); }
        bound();
        let s = strip(start, pos);
        let n, ok = parse_int(s, base);
        if !ok { bail(pos, "integer out of range"); }
        return Value.Int { v: n };
    }

    fn whole_float(s: u8[:]) -> bool {
        var i = 0;
        if s.len > 0 && (s[0] == '+' || s[0] == '-') { i = 1; }
        var saw_dot = false;
        var any = false;
        while i < s.len {
            let c = s[i];
            if c == '.' {
                if saw_dot { return false; }
                saw_dot = true;
            } else if c >= '0' && c <= '9' {
                if saw_dot && c != '0' { return false; }
                any = true;
            } else {
                return false;
            }
            i++;
        }
        return saw_dot && any;
    }

    fn take_decimal(begin: i64) -> Value {
        if pos >= text.len || !digit(text[pos]) { bail(pos, "bad number"); }
        if text[pos] == '0' {
            pos++;
            if pos < text.len && digit(text[pos]) { bail(pos, "leading zero"); }
        } else {
            eat_digits("bad number");
        }
        var is_float = false;
        if pos < text.len && text[pos] == '.' {
            is_float = true;
            pos++;
            eat_digits("bad float");
        }
        if pos < text.len && (text[pos] == 'e' || text[pos] == 'E') {
            is_float = true;
            pos++;
            if pos < text.len && (text[pos] == '+' || text[pos] == '-') { pos++; }
            eat_digits("bad float");
        }
        bound();
        let s = strip(begin, pos);
        if is_float {
            // parse_flt is off by one unit on a long ".0" mantissa. The integer is exact.
            if whole_float(s) {
                var end = 0;
                while end < s.len && s[end] != '.' { end++; }
                let n, ok = parse_int(s[..end]);
                if ok && n != 0 { return Value.Float { v: n }; }
            }
            let v, ok = parse_flt(s);
            if !ok { bail(pos, "bad float"); }
            return Value.Float { v: v };
        }
        let n, ok = parse_int(s);
        if !ok { bail(pos, "integer out of range"); }
        return Value.Int { v: n };
    }

    fn at_word(w: u8[:]) -> bool {
        if pos + w.len > text.len || text[pos..pos + w.len] != w { return false; }
        let after = pos + w.len;
        if after < text.len && bare(text[after]) { return false; }
        return true;
    }

    fn take_number() -> Value {
        let begin = pos;
        var neg = false;
        var signed = false;
        if text[pos] == '+' || text[pos] == '-' {
            signed = true;
            neg = text[pos] == '-';
            pos++;
            if pos >= text.len { bail(pos, "bad value"); }
        }
        if at_word("inf") {
            pos += 3;
            return Value.Float { v: ieee_inf(neg) };
        }
        if at_word("nan") {
            pos += 3;
            return Value.Float { v: ieee_nan() };
        }
        if !signed && ahead(4, '-') { return take_date(begin); }
        if !signed && ahead(2, ':') { return take_time(begin); }
        if pos + 1 < text.len && text[pos] == '0' && (text[pos + 1] == 'x' || text[pos + 1] == 'o' || text[pos + 1] == 'b') {
            if signed { bail(pos, "bad integer"); }
            return take_radix();
        }
        return take_decimal(begin);
    }

    if pos >= text.len { bail(pos, "expected a value"); }
    let c = text[pos];
    if c == '"' || c == '\'' { return Value.String { s: read_string(text, pos, decoded) }; }
    if at_word("true") {
        pos += 4;
        return Value.Bool { v: true };
    }
    if at_word("false") {
        pos += 5;
        return Value.Bool { v: false };
    }
    if c == '+' || c == '-' || c == 'i' || c == 'n' || digit(c) { return take_number(); }
    bail(pos, "expected a value");
}

// A nested function cannot store a link into a pool it closed over.
fn add(doc: Node[>..]&, parent: Node&, key: const u8[:], val: Value) -> Node& {
    let node .= doc.push(Node { next: null, first: null, key: key, val: val });
    // ponytail: walk siblings to append. A last-child link if a document is huge.
    if parent.first {
        var c = parent.first;
        while c {
            if c.next { c .= c.next; }
            else {
                c.next .= node;
                break;
            }
        }
    } else {
        parent.first .= node;
    }
    match parent.val {
        Table t => { parent.val = Value.Table { count: t.count + 1, kind: t.kind }; },
        Array a => { parent.val = Value.Array { count: a.count + 1, items: a.items }; },
        _ => { abort("toml: not a container"); },
    }
    return node;
}

fn is_table(n: Node&) -> bool {
    match n.val {
        Table => { return true; },
        _ => { return false; },
    }
}

fn last_table(n: Node&) -> Node& {
    var c = n.first;
    while c {
        if c.next { c .= c.next; }
        else {
            match c.val {
                Table => { return c; },
                _ => { abort("toml: array element"); },
            }
        }
    }
    abort("toml: empty array of tables");
}

// A header's middle key. Missing pieces are implicit, so a later [x] can
// define a parent that [x.y.z] already walked through.
fn enter_header(doc: Node[>..]&, parent: Node&, key: const u8[:], at: i64) -> Node& {
    let c = find(parent, key);
    guard c else { return add(doc, parent, key, Value.Table { count: 0, kind: TableKind.Implicit }); }
    match c.val {
        Table t => {
            if t.kind == TableKind.Inline { bail(at, "inline table"); }
            return c;
        },
        Array a => {
            if a.items != Items.Tables { bail(at, "not a table"); }
            return last_table(c);
        },
        _ => { bail(at, "not a table"); },
    }
}

// A dotted key defines each table before the last segment. It may extend a
// table it defined itself. A header-defined table stays closed.
fn enter_dotted(doc: Node[>..]&, parent: Node&, key: const u8[:], at: i64) -> Node& {
    let c = find(parent, key);
    guard c else { return add(doc, parent, key, Value.Table { count: 0, kind: TableKind.Dotted }); }
    match c.val {
        Table t => {
            if t.kind == TableKind.Inline || t.kind == TableKind.Defined { bail(at, "dotted key"); }
            if t.kind == TableKind.Implicit {
                c.val = Value.Table { count: t.count, kind: TableKind.Dotted };
            }
            return c;
        },
        _ => { bail(at, "dotted key"); },
    }
}

fn open_table(doc: Node[>..]&, parent: Node&, key: const u8[:], at: i64) -> Node& {
    let c = find(parent, key);
    guard c else { return add(doc, parent, key, Value.Table { count: 0, kind: TableKind.Defined }); }
    match c.val {
        Table t => {
            if t.kind != TableKind.Implicit { bail(at, "duplicate table"); }
            c.val = Value.Table { count: t.count, kind: TableKind.Defined };
            return c;
        },
        _ => { bail(at, "duplicate table"); },
    }
}

fn open_aot(doc: Node[>..]&, parent: Node&, key: const u8[:], at: i64) -> Node& {
    let found = find(parent, key);
    var arr: Node? = null;
    if found {
        match found.val {
            Array a => {
                if a.items != Items.Tables { bail(at, "not an array of tables"); }
                arr .= found;
            },
            _ => { bail(at, "not an array of tables"); },
        }
    } else {
        arr .= add(doc, parent, key, Value.Array { count: 0, items: Items.Tables });
    }
    guard arr else { bail(at, "not an array of tables"); }
    return add(doc, arr, "", Value.Table { count: 0, kind: TableKind.Defined });
}

fn walk_dotted(text: u8[:], pos: i64&, doc: Node[>..]&, decoded: u8[>..]&, parent: Node&) -> Node&, const u8[:] {
    var table .= parent;
    var key = read_key(text, pos, decoded);
    loop {
        skip_ws(text, pos, false);
        if pos < text.len && text[pos] == '.' {
            pos++;
            table .= enter_dotted(doc, table, key, pos);
            key = read_key(text, pos, decoded);
            continue;
        }
        return table, key;
    }
}

fn walk_header(text: u8[:], pos: i64&, doc: Node[>..]&, decoded: u8[>..]&, parent: Node&) -> Node&, const u8[:] {
    var table .= parent;
    var key = read_key(text, pos, decoded);
    loop {
        skip_ws(text, pos, false);
        if pos < text.len && text[pos] == '.' {
            pos++;
            table .= enter_header(doc, table, key, pos);
            key = read_key(text, pos, decoded);
            continue;
        }
        return table, key;
    }
}

recursive fn fill_inline(text: u8[:], pos: i64&, doc: Node[>..]&, decoded: u8[>..]&, node: Node&) {
    skip_ws(text, pos, false);
    if pos < text.len && text[pos] == '}' {
        pos++;
        return;
    }
    loop {
        let table, key .= walk_dotted(text, pos, doc, decoded, node);
        skip_ws(text, pos, false);
        if pos >= text.len || text[pos] != '=' { bail(pos, "expected '='"); }
        pos++;
        skip_ws(text, pos, false);
        attach(text, pos, doc, decoded, table, key);
        skip_ws(text, pos, false);
        if pos >= text.len { bail(pos, "unclosed inline table"); }
        if text[pos] == ',' {
            pos++;
            skip_ws(text, pos, false);
            if pos < text.len && text[pos] == '}' { bail(pos, "trailing comma"); }
            continue;
        }
        if text[pos] == '}' {
            pos++;
            return;
        }
        bail(pos, "expected ',' or '}'");
    }
}

recursive fn attach(text: u8[:], pos: i64&, doc: Node[>..]&, decoded: u8[>..]&, parent: Node&, key: const u8[:]) {
    if is_table(parent) && find(parent, key) { bail(pos, "duplicate key"); }
    if pos >= text.len { bail(pos, "expected a value"); }
    let c = text[pos];
    if c == '[' {
        let node .= add(doc, parent, key, Value.Array { count: 0, items: Items.Values });
        pos++;
        skip_ws(text, pos, true);
        if pos < text.len && text[pos] == ']' {
            pos++;
            return;
        }
        loop {
            attach(text, pos, doc, decoded, node, "");
            skip_ws(text, pos, true);
            if pos >= text.len { bail(pos, "unclosed array"); }
            if text[pos] == ',' {
                pos++;
                skip_ws(text, pos, true);
                if pos < text.len && text[pos] == ']' {
                    pos++;
                    return;
                }
                continue;
            }
            if text[pos] == ']' {
                pos++;
                return;
            }
            bail(pos, "expected ',' or ']'");
        }
    }
    if c == '{' {
        let node .= add(doc, parent, key, Value.Table { count: 0, kind: TableKind.Inline });
        pos++;
        fill_inline(text, pos, doc, decoded, node);
        return;
    }
    add(doc, parent, key, read_value(text, pos, decoded));
}

// The root table, or null and a message. doc holds every node. decoded holds
// the bytes of strings that used an escape. Both belong to the caller.
fn parse(text: u8[:], doc: Node[>..]&, decoded: u8[>..]&) -> Node?, u8[>..] {
    var pos = 0;
    let bad = utf8_bad(text);
    if bad >= 0 { return null, str("toml: invalid utf-8 at byte ", bad); }
    if text.len >= 3 && text[0] == 0xEF && text[1] == 0xBB && text[2] == 0xBF { pos = 3; }

    let root .= doc.push(Node {
        next: null,
        first: null,
        key: "",
        val: Value.Table { count: 0, kind: TableKind.Defined },
    });
    var current .= root;

    loop {
        skip_gap(text, pos);
        if pos >= text.len { return root, str(""); }
        if text[pos] == '[' {
            var aot = false;
            pos++;
            if pos < text.len && text[pos] == '[' {
                aot = true;
                pos++;
            }
            let parent, key .= walk_header(text, pos, doc, decoded, root);
            if pos >= text.len || text[pos] != ']' { bail(pos, "expected ']'"); }
            pos++;
            if aot {
                if pos >= text.len || text[pos] != ']' { bail(pos, "expected ']'"); }
                pos++;
            }
            let at = pos;
            finish_line(text, pos);
            if aot { current .= open_aot(doc, parent, key, at); }
            else { current .= open_table(doc, parent, key, at); }
            continue;
        }
        let table, key .= walk_dotted(text, pos, doc, decoded, current);
        skip_ws(text, pos, false);
        if pos >= text.len || text[pos] != '=' { bail(pos, "expected '='"); }
        pos++;
        skip_ws(text, pos, false);
        attach(text, pos, doc, decoded, table, key);
        finish_line(text, pos);
    }
}

fn ::main() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse("a = 1\n", doc, decoded);
    if err.len != 0 { print(err); }
    else if root { print("goose tests/self_check.goose"); }
}
