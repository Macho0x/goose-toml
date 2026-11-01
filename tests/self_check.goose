import toml from "..";
import toml.parse;

fn fail(why: u8[:]) {
    print(why);
    exit(1);
}

fn load(text: u8[:], doc: parse::Node[>..]&, decoded: u8[>..]&) -> parse::Node? {
    let root, err = parse::parse(text, doc, decoded);
    if err.len != 0 { fail(err); }
    return root;
}

fn reject(text: u8[:]) {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = parse::parse(text, doc, decoded);
    if err.len < 6 || err[..6] != "toml: " || root { fail(text); }
}

fn need_str(n: parse::Node?, want: u8[:], why: u8[:]) {
    let s, ok = parse::string_of(n);
    if !ok || s != want { fail(why); }
}

fn need_int(n: parse::Node?, want: i64, why: u8[:]) {
    let v, ok = parse::int_of(n);
    if !ok || v != want { fail(why); }
}

fn need_float(n: parse::Node?, want: f64, why: u8[:]) {
    let v, ok = parse::float_of(n);
    if !ok || v != want { fail(why); }
}

fn need_bool(n: parse::Node?, want: bool, why: u8[:]) {
    let v, ok = parse::bool_of(n);
    if !ok || v != want { fail(why); }
}

fn need_time(n: parse::Node?, when: parse::When, text: u8[:], why: u8[:]) {
    let got, s, ok = parse::time_of(n);
    if !ok || got != when || s != text { fail(why); }
}

fn basics() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("name = \"goose\"\nint = +99\nbig = 1_000\nhex = 0xDEAD\noct = 0o755\nbin = 0b11010110\nf = 1.5\nsc = 5e2\nmillion = 1e06\nhalf = 0.5\nz = -0.0\npz = +0.0\npos = inf\nneg = -inf\nn = nan\nok = true\nno = false\n", doc, decoded);
    need_str(parse::child(root, "name"), "goose", "name");
    need_int(parse::child(root, "int"), 99, "+99");
    need_int(parse::child(root, "big"), 1000, "1_000");
    need_int(parse::child(root, "hex"), 0xDEAD, "hex");
    need_int(parse::child(root, "oct"), 493, "oct");
    need_int(parse::child(root, "bin"), 214, "bin");
    need_float(parse::child(root, "f"), 1.5, "1.5");
    need_float(parse::child(root, "sc"), 500.0, "5e2");
    need_float(parse::child(root, "million"), 1000000.0, "1e06");
    need_float(parse::child(root, "half"), 0.5, "0.5");
    let z, zok = parse::float_of(parse::child(root, "z"));
    if !zok || !(z == 0.0) || !((1.0 / z) < 0.0) { fail("-0.0"); }
    let pz, pok = parse::float_of(parse::child(root, "pz"));
    if !pok || !(pz == 0.0) || !((1.0 / pz) > 0.0) { fail("+0.0"); }
    let pinf, iok = parse::float_of(parse::child(root, "pos"));
    if !iok || !(pinf > 1e308) { fail("+inf"); }
    let ninf, nok = parse::float_of(parse::child(root, "neg"));
    if !nok || !(ninf < -1e308) { fail("-inf"); }
    let nan, nnok = parse::float_of(parse::child(root, "n"));
    if !nnok || nan == nan { fail("nan"); }
    need_bool(parse::child(root, "ok"), true, "true");
    need_bool(parse::child(root, "no"), false, "false");
    var doc2: parse::Node[>..] = [];
    var decoded2: u8[>..] = [];
    let more .= load("pinf = +inf\nnnan = -nan\nbeef = 0xdead_beef\nempty = {}\n", doc2, decoded2);
    let pinf, pok = parse::float_of(parse::child(more, "pinf"));
    if !pok || !(pinf > 1e308) { fail("+inf"); }
    let nnan, nok = parse::float_of(parse::child(more, "nnan"));
    if !nok || nnan == nnan { fail("-nan"); }
    need_int(parse::child(more, "beef"), 0xdeadbeef, "beef");
    let empty = parse::child(more, "empty");
    if !empty || parse::child(empty, "a") { fail("empty inline"); }
}

fn limits() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("hi = 9223372036854775807\nlo = -9223372036854775808\n", doc, decoded);
    need_int(parse::child(root, "hi"), 9223372036854775807, "max");
    need_int(parse::child(root, "lo"), -9223372036854775808, "min");
    reject("n = 9223372036854775808\n");
    reject("n = -9223372036854775809\n");
    reject("n = 01\n");
    reject("n = 0x_1\n");
    reject("n = truex\n");
    reject("n = 1__2\n");
}

fn strings() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("plain = \"a\\nb\"\nlit = 'C:\\Users\\nodejs\\templates'\nuni = \"Jos\\u00E9\"\nml = \"\"\"\nRoses are red\nViolets are blue\"\"\"\ntrim = \"\"\"\nThe quick brown \\\n\n  fox.\"\"\"\nedge = \"\"\"\"This,\" she said.\"\"\"\n", doc, decoded);
    need_str(parse::child(root, "plain"), "a\nb", "escape");
    need_str(parse::child(root, "lit"), "C:\\Users\\nodejs\\templates", "literal");
    need_str(parse::child(root, "uni"), "Jos\xC3\xA9", "unicode");
    need_str(parse::child(root, "ml"), "Roses are red\nViolets are blue", "multiline");
    need_str(parse::child(root, "trim"), "The quick brown fox.", "backslash");
    need_str(parse::child(root, "edge"), "\"This,\" she said.", "quotes");
}

fn times() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("odt = 1979-05-27T07:32:00Z\nodt2 = 1979-05-27 07:32:00Z\nldt = 1979-05-27T07:32:00\nld = 1979-05-27\nlt = 07:32:00\nleap = 1972-06-30T23:59:60Z\nfeb = 2000-02-29\n", doc, decoded);
    need_time(parse::child(root, "odt"), parse::When.Offset, "1979-05-27T07:32:00Z", "odt");
    need_time(parse::child(root, "odt2"), parse::When.Offset, "1979-05-27 07:32:00Z", "space");
    need_time(parse::child(root, "ldt"), parse::When.LocalDateTime, "1979-05-27T07:32:00", "ldt");
    need_time(parse::child(root, "ld"), parse::When.LocalDate, "1979-05-27", "ld");
    need_time(parse::child(root, "lt"), parse::When.LocalTime, "07:32:00", "lt");
    need_time(parse::child(root, "leap"), parse::When.Offset, "1972-06-30T23:59:60Z", "leap second");
    need_time(parse::child(root, "feb"), parse::When.LocalDate, "2000-02-29", "leap day");
    reject("d = 1979-02-29\n");
    reject("d = 1900-02-29\n");
    reject("d = 1979-04-31\n");
}

fn dotted() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("3.14159 = \"pi\"\n[dog.\"tater.man\"]\ntype.name = \"pug\"\n", doc, decoded);
    need_str(parse::child(parse::child(root, "3"), "14159"), "pi", "pi");
    let dog = parse::child(root, "dog");
    let tater = parse::child(dog, "tater.man");
    need_str(parse::child(parse::child(tater, "type"), "name"), "pug", "pug");
}

fn tables() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("[x.y.z.w]\na = 1\n[x]\nk = 2\n", doc, decoded);
    need_int(parse::child(parse::child(root, "x"), "k"), 2, "super");
    let y = parse::child(parse::child(root, "x"), "y");
    let z = parse::child(y, "z");
    need_int(parse::child(parse::child(z, "w"), "a"), 1, "deep");

    var doc2: parse::Node[>..] = [];
    var decoded2: u8[>..] = [];
    let fruit .= load("[fruit.apple]\na = 1\n[animal]\nb = 2\n[fruit.orange]\nc = 3\n[fruit]\nk = 4\n", doc2, decoded2);
    need_int(parse::child(parse::child(parse::child(fruit, "fruit"), "apple"), "a"), 1, "apple");
    need_int(parse::child(parse::child(fruit, "animal"), "b"), 2, "animal");
    need_int(parse::child(parse::child(parse::child(fruit, "fruit"), "orange"), "c"), 3, "orange");
    need_int(parse::child(parse::child(fruit, "fruit"), "k"), 4, "fruit key");

    var doc3: parse::Node[>..] = [];
    var decoded3: u8[>..] = [];
    let sub .= load("[fruit]\napple.color = \"red\"\n\n[fruit.apple.texture]\nsmooth = true\n", doc3, decoded3);
    let apple = parse::child(parse::child(sub, "fruit"), "apple");
    need_str(parse::child(apple, "color"), "red", "color");
    need_bool(parse::child(parse::child(apple, "texture"), "smooth"), true, "smooth");
}

fn fruits() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let src = """
        [[fruits]]
        name = "apple"

        [fruits.physical]
        color = "red"
        shape = "round"

        [[fruits.varieties]]
        name = "red delicious"

        [[fruits.varieties]]
        name = "granny smith"

        [[fruits]]
        name = "banana"

        [[fruits.varieties]]
        name = "plantain"
        """;
    let root .= load(src, doc, decoded);
    let list = parse::child(root, "fruits");
    let apple = parse::at(list, 0);
    let banana = parse::at(list, 1);
    if parse::at(list, 2) { fail("two fruits"); }
    need_str(parse::child(apple, "name"), "apple", "apple name");
    let physical = parse::child(apple, "physical");
    need_str(parse::child(physical, "color"), "red", "color");
    need_str(parse::child(physical, "shape"), "round", "shape");
    let varieties = parse::child(apple, "varieties");
    need_str(parse::child(parse::at(varieties, 0), "name"), "red delicious", "red");
    need_str(parse::child(parse::at(varieties, 1), "name"), "granny smith", "granny");
    need_str(parse::child(banana, "name"), "banana", "banana");
    need_str(parse::child(parse::at(parse::child(banana, "varieties"), 0), "name"), "plantain", "plantain");
    if parse::child(banana, "physical") { fail("banana physical"); }
}

fn arrays() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root .= load("a = [1, \"x\", true,]\nb = [\n  1, # c\n  2,\n]\ninline = { type.name = \"pug\" }\npoints = [ { x = 1, y = 2 }, { x = 7 } ]\n", doc, decoded);
    let a = parse::child(root, "a");
    need_int(parse::at(a, 0), 1, "a0");
    need_str(parse::at(a, 1), "x", "a1");
    need_bool(parse::at(a, 2), true, "a2");
    if parse::at(a, 3) { fail("a len"); }
    let b = parse::child(root, "b");
    need_int(parse::at(b, 0), 1, "b0");
    need_int(parse::at(b, 1), 2, "b1");
    let pug = parse::child(parse::child(parse::child(root, "inline"), "type"), "name");
    need_str(pug, "pug", "inline");
    let p0 = parse::at(parse::child(root, "points"), 0);
    need_int(parse::child(p0, "x"), 1, "x");
    need_int(parse::child(p0, "y"), 2, "y");
    need_int(parse::child(parse::at(parse::child(root, "points"), 1), "x"), 7, "x7");
}

fn rejects() {
    reject("[fruit]\napple.color = \"red\"\n\n[fruit.apple]\n");
    reject("fruit.apple = 1\n\n[fruit.apple]\n");
    reject("fruits = []\n\n[[fruits]]\n");
    reject("a = 1\na = 2\n");
    reject("t = { a = 1, }\n");
    reject("t = { a = 1,\n b = 2 }\n");
    reject("[fruit]\n[fruit]\n");
    reject("\x80");
    reject("s = \"\n\"\n");
}

fn edges() {
    var doc: parse::Node[>..] = [];
    var decoded: u8[>..] = [];
    let empty .= load("", doc, decoded);
    if parse::child(empty, "a") { fail("empty"); }
    var doc2: parse::Node[>..] = [];
    var decoded2: u8[>..] = [];
    let commented .= load("# hi\n\na = 1 # tail\n", doc2, decoded2);
    need_int(parse::child(commented, "a"), 1, "comment");
    var doc3: parse::Node[>..] = [];
    var decoded3: u8[>..] = [];
    let crlf .= load("a = 1\r\nb = 2\r\n", doc3, decoded3);
    need_int(parse::child(crlf, "a"), 1, "cr a");
    need_int(parse::child(crlf, "b"), 2, "cr b");
    var doc4: parse::Node[>..] = [];
    var decoded4: u8[>..] = [];
    let bom .= load("\xEF\xBB\xBFa = 1\n", doc4, decoded4);
    need_int(parse::child(bom, "a"), 1, "bom");
}

fn self_check() -> bool {
    basics();
    limits();
    strings();
    times();
    dotted();
    tables();
    fruits();
    arrays();
    rejects();
    edges();
    return true;
}

fn ::main() {
    if !self_check() { exit(1); }
    print("toml ok");
}
