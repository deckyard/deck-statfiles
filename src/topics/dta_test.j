# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - white-box tests for the dta topic. Spliced into
# statfiles_test.j via include. The sample files are in fixtures/dtafiles_test.j.

include "fixtures/dtafiles_test.j";

/**
 * A sample file's bytes.
 *
 * @param lines {list of string} its base64 constant
 * @return {bytes} the file
 */
func dtaSample(lines as list of string) {
    return encoding.fromText("base64", strings.join($lines, ""));
}

/**
 * Read a sample file with the default options.
 *
 * @param lines {list of string} its base64 constant
 * @return {Dataset} the dataset
 */
func dtaOpen(lines as list of string) {
    return readDta(dtaSample($lines), options());
}

/**
 * Read bytes with the default options, for `assertThrowsWith`.
 *
 * @param b {bytes} the file
 * @return {Dataset} the dataset
 */
func dtaReadBytes(b as bytes) {
    return readDta($b, options());
}

/**
 * The kind of error reading a file throws.
 *
 * @param b {bytes} the file
 * @param opts {Options} the options
 * @return {string} the kind, `""` when the file reads
 */
func dtaKind(b as bytes, opts as Options) {
    try {
        readDta($b, $opts);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * Overwrite bytes.
 *
 * @param b {bytes} the file
 * @param at {int} the first byte to change
 * @param values {list of int} the new bytes
 * @return {bytes} the changed copy
 */
func dtaPatch(b as bytes, at as int, values as list of int) {
    def i as int init $at;
    for (def v in $values) {
        $b[$i] = $v;
        $i = $i + 1;
    }
    return $b;
}

/**
 * The offset of an ASCII text in a file.
 *
 * @param b {bytes} the file
 * @param text {string} the text
 * @return {int} its first offset, -1 if absent
 */
func dtaFind(b as bytes, text as string) {
    return binary.indexOf($b, convert.bytesFromString("utf-8", $text));
}

/**
 * The storage types of a dataset's variables.
 *
 * @param ds {Dataset} the dataset
 * @return {list of string} one per variable
 */
func dtaStorages(ds as Dataset) {
    def out as list of string init [];
    for (def v in $ds.variables) {
        $out[] = $v.storage;
    }
    return $out;
}

/**
 * A variable's cells as `text` writes them.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable
 * @return {list of string} one per row
 */
func dtaCells(ds as Dataset, name as string) {
    def out as list of string init [];
    for (def r in 0..$ds.rowCount) {
        $out[] = text($ds, $name, $r);
    }
    return $out;
}

func testDtaDetect() {
    for (def lines in [
        DTA_H104_BASE64,
        DTA_H111BE_BASE64,
        DTA_PY115_BASE64,
        DTA_PD117BE_BASE64,
        DTA_PY118_BASE64,
        DTA_PD119BE_BASE64
    ]) {
        testing.assertEqual(detect(dtaSample($lines)), "dta");
    }
    testing.assertFalse(looksLikeDta(binary.make(0)));
    testing.assertFalse(looksLikeDta(convert.bytesFromString("utf-8", "<stata_dta><header>")));
    # 116 was never released; 115 with byte order 3 is no dta either
    testing.assertFalse(looksLikeDta(dtaPatch(binary.make(8), 0, [116, 2, 1, 0])));
    testing.assertFalse(looksLikeDta(dtaPatch(binary.make(8), 0, [115, 3, 1, 0])));
    testing.assertTrue(looksLikeDta(dtaPatch(binary.make(8), 0, [115, 2, 1, 0])));
}

func testDta118Pyreadstat() {
    def ds as Dataset init dtaOpen(DTA_PY118_BASE64);
    testing.assertEqual($ds.format, "dta");
    testing.assertEqual($ds.version, "118");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.label, "Ünïcode dataset");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(names($ds), ["byt", "i16", "i32", "f32", "dbl", "txt"]);
    # pyreadstat stores a float32 column as double
    testing.assertEqual(dtaStorages($ds), ["long", "long", "long", "double", "double", "str9"]);
    testing.assertEqual(column($ds, "byt"), [1.0, -127.0, 100.0, 7.0, 0.0]);
    testing.assertEqual(column($ds, "i32"), [70000.0, -2147483647.0, 2147483620.0, 1.0, 2.0]);
    testing.assertEqual(dtaCells($ds, "f32"), ["1.5", "-2.25", "1.0000000150474662e+30", ".", "3"]);
    testing.assertEqual($ds.numbers[3][3], 0.0);
    testing.assertEqual(dtaCells($ds, "dbl"), ["1.25", ".", ".a", ".z", "-1e+300"]);
    testing.assertEqual($ds.missing[4], ["", ".", ".a", ".z", ""]);
    testing.assertEqual(textColumn($ds, "txt"), ["Grüße", "日本語", "", "plain", "x"]);
    def v as Variable init variable($ds, "byt");
    testing.assertEqual($v.label, "A byte");
    testing.assertEqual($v.type, "numeric");
    testing.assertEqual($v.width, 0);
    testing.assertEqual($v.valueLabels, {"1": "one", "7": "seven", "100": "hundred"});
    testing.assertEqual(labelOf($ds, "byt", 3), "seven");
    testing.assertEqual(variable($ds, "txt").label, "Text ünïcode");
    testing.assertEqual(variable($ds, "txt").type, "string");
    testing.assertEqual(variable($ds, "txt").width, 9);
    testing.assertEqual(variable($ds, "f32").format, "%9.2f");
    testing.assertEqual(variable($ds, "dbl").missingValues, []);
}

func testDta117BigEndian() {
    def ds as Dataset init dtaOpen(DTA_PD117BE_BASE64);
    testing.assertEqual($ds.version, "117");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.label, "Österreich");
    testing.assertEqual(
        dtaStorages($ds),
        ["byte", "int", "long", "float", "double", "str6", "strL", "byte"]);
    testing.assertEqual(column($ds, "b"), [1.0, 2.0, 3.0, 4.0]);
    testing.assertEqual(column($ds, "h"), [1000.0, -1000.0, 0.0, 7.0]);
    testing.assertEqual(column($ds, "l"), [100000.0, -100000.0, 0.0, 9.0]);
    testing.assertEqual(dtaCells($ds, "f"), ["0.5", ".", "-1", "2.5"]);
    testing.assertEqual(dtaCells($ds, "d"), ["3.141592653589793", "-2.5", ".", "1e-10"]);
    testing.assertEqual(textColumn($ds, "s"), ["café", "naïve", "", "Zürich"]);
    testing.assertEqual(variable($ds, "s").label, "Straße");
    testing.assertEqual(textColumn($ds, "note"), ["shared", "shared", "", "other text"]);
    testing.assertEqual(variable($ds, "note").width, 0);
    testing.assertEqual(variable($ds, "town").valueLabels, {"0": "Graz", "1": "Linz", "2": "Wien"});
    testing.assertEqual(labelOf($ds, "town", 1), "Wien");
}

func testDtaBigEndianStrls() {
    for (def lines in [DTA_PD118BE_BASE64, DTA_PD119BE_BASE64]) {
        def ds as Dataset init dtaOpen($lines);
        testing.assertEqual(dtaStorages($ds), ["double", "strL", "strL"]);
        testing.assertEqual(dtaCells($ds, "x"), ["1", ".", "3"]);
        testing.assertEqual(textColumn($ds, "t"), ["ünï", "", "日本"]);
        testing.assertEqual(textColumn($ds, "u"), ["a", "a", "b"]);
    }
    testing.assertEqual(dtaOpen(DTA_PD119BE_BASE64).label, "big 119");
    # the first GSO as binary (type 129): its bytes as they are, the NUL dropped as trailing
    def b as bytes init dtaSample(DTA_PD118BE_BASE64);
    testing.assertEqual(
        textColumn(dtaReadBytes(dtaPatch($b, dtaFind($b, "GSO") + 15, [129])), "t")[0],
        "ünï");
}

func testDtaLongStrls() {
    for (def lines in [DTA_PY117STRL_BASE64, DTA_PY119_BASE64]) {
        def ds as Dataset init dtaOpen($lines);
        testing.assertEqual(variable($ds, "big").storage, "strL");
        def big as list of string init textColumn($ds, "big");
        testing.assertEqual(len($big[0]), 2103);
        testing.assertTrue(strings.endsWith($big[0], "LLend"));
        testing.assertEqual($big[1..3], ["", "short"]);
    }
    testing.assertEqual(dtaOpen(DTA_PY119_BASE64).version, "119");
}

func testDta118ValueLabelsAndCharacteristics() {
    for (def lines in [DTA_PD118_BASE64, DTA_PD118CH_BASE64]) {
        def ds as Dataset init dtaOpen($lines);
        testing.assertEqual($ds.label, "Schweiz €");
        testing.assertEqual(dtaStorages($ds), ["byte", "int", "byte", "str6"]);
        testing.assertEqual(column($ds, "b"), [-1.0, 0.0, 100.0]);
        testing.assertEqual(column($ds, "h"), [-300.0, 0.0, 300.0]);
        testing.assertEqual(variable($ds, "city").label, "Stadt ü");
        testing.assertEqual(variable($ds, "city").valueLabels, {"0": "Genève", "1": "Zürich"});
        testing.assertEqual(labelOf($ds, "city", 0), "Zürich");
        testing.assertEqual(textColumn($ds, "s"), ["€uro", "ß", ""]);
    }
}

func testDtaMissingCodes() {
    for (def lines in [DTA_H115_BASE64, DTA_H113BE_BASE64]) {
        def ds as Dataset init dtaOpen($lines);
        testing.assertEqual(dtaStorages($ds), ["byte", "int", "long", "float", "double", "str5"]);
        testing.assertEqual(dtaCells($ds, "b"), ["100", ".", ".a", ".z", "-127"]);
        testing.assertEqual(dtaCells($ds, "i"), ["32740", ".", ".a", ".z", "-32767"]);
        testing.assertEqual(dtaCells($ds, "l"), ["2147483620", ".", ".a", ".z", "-2147483647"]);
        testing.assertEqual(dtaCells($ds, "f"), ["1", ".", ".a", ".z", "-1.5"]);
        testing.assertEqual(dtaCells($ds, "d"), ["2", ".", ".b", ".z", "-2.5"]);
        testing.assertEqual($ds.numbers[4], [2.0, 0.0, 0.0, 0.0, -2.5]);
        testing.assertEqual(present($ds, "l"), [2147483620.0, -2147483647.0]);
        testing.assertEqual(textColumn($ds, "s"), ["abcde", "ab", "", "x", "eé"]);
        testing.assertEqual(variable($ds, "s").label, "five");
        try {
            column($ds, "b");
            missed();
        } catch (e) {
            testing.assertEqual($e.kind, ERROR_KIND);
        }
    }
    def ds as Dataset init dtaOpen(DTA_H115_BASE64);
    testing.assertEqual(
        variable($ds, "b").valueLabels,
        {"1": "yes", "100": "hundred", "101": "sysmiss", ".a": "dot a"});
    testing.assertEqual(labelOf($ds, "b", 2), "dot a");
    testing.assertEqual(labelOf($ds, "b", 0), "hundred");
}

func testDtaPyreadstat113And115() {
    def ds as Dataset init dtaOpen(DTA_PY113_BASE64);
    testing.assertEqual($ds.version, "113");
    testing.assertEqual($ds.label, "v113");
    testing.assertEqual(dtaCells($ds, "score"), ["0.5", ".", "2"]);
    testing.assertEqual(textColumn($ds, "name"), ["ann", "bob", "carl"]);
    testing.assertEqual(variable($ds, "id").valueLabels, {"1": "first", "3": "third"});
    $ds = dtaOpen(DTA_PY115_BASE64);
    testing.assertEqual($ds.version, "115");
    testing.assertEqual(variable($ds, "score").label, "The score");
    testing.assertEqual(variable($ds, "name").format, "%-9s");
}

func testDtaOldFormats() {
    def all as list of list of string init [
        DTA_H104_BASE64,
        DTA_H105BE_BASE64,
        DTA_H108_BASE64,
        DTA_H110_BASE64,
        DTA_H111BE_BASE64
    ];
    def versions as list of string init ["104", "105", "108", "110", "111"];
    for (def i in 0..len($all)) {
        def ds as Dataset init dtaOpen($all[$i]);
        testing.assertEqual($ds.version, $versions[$i]);
        testing.assertEqual($ds.label, "old" + $versions[$i]);
        testing.assertEqual(names($ds), ["a", "bb", "c", "d", "e", "s"]);
        testing.assertEqual(dtaStorages($ds), ["byte", "int", "long", "float", "double", "str4"]);
        testing.assertEqual(dtaCells($ds, "a"), ["1", ".", "126"]);
        testing.assertEqual(dtaCells($ds, "bb"), ["2", ".", "32766"]);
        testing.assertEqual(dtaCells($ds, "c"), ["3", ".", "2147483646"]);
        testing.assertEqual(dtaCells($ds, "d"), ["1.5", ".", "-1"]);
        testing.assertEqual(dtaCells($ds, "e"), ["2.5", ".", "-2"]);
        testing.assertEqual(textColumn($ds, "s"), ["ab", "abcd", ""]);
        testing.assertEqual(variable($ds, "a").label, "byte var");
        testing.assertEqual(labelOf($ds, "a", 0), "one");
    }
    testing.assertEqual(
        variable(dtaOpen(DTA_H105BE_BASE64), "a").valueLabels,
        {"1": "one", "126": "max"});
    testing.assertEqual(
        variable(dtaOpen(DTA_H108_BASE64), "a").valueLabels,
        {"1": "one", "126": "eight chars long"});
    testing.assertEqual(variable(dtaOpen(DTA_H110_BASE64), "d").format, "%9.0g");
}

func testDtaEncodingOption() {
    def opts as Options init options();
    $opts.encoding = "ISO-8859-1";
    def ds as Dataset init readDta(dtaSample(DTA_PD114BE_BASE64), $opts);
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual(textColumn($ds, "s"), ["Ärger", "ok"]);
    testing.assertEqual(variable($ds, "c").valueLabels, {"0": "ja", "1": "nein"});
    # UTF-8 text read as Windows-1252 decodes, as mojibake
    $opts.encoding = "windows-1252";
    testing.assertEqual(textColumn(readDta(dtaSample(DTA_PD118_BASE64), $opts), "s")[1], "ÃŸ");
    # Latin-1 text is no UTF-8, and ASCII lacks the byte
    $opts.encoding = "utf-8";
    testing.assertEqual(dtaKind(dtaSample(DTA_PD117BE_BASE64), $opts), ERROR_KIND);
    $opts.encoding = "ascii";
    testing.assertEqual(dtaKind(dtaSample(DTA_H115_BASE64), $opts), ERROR_KIND);
    $opts.encoding = "klingon";
    testing.assertEqual(dtaKind(dtaSample(DTA_H115_BASE64), $opts), ERROR_KIND);
}

func testDtaCellCap() {
    def opts as Options init options();
    $opts.maxCells = 29;
    testing.assertEqual(dtaKind(dtaSample(DTA_H115_BASE64), $opts), "limit");
    testing.assertEqual(dtaKind(dtaSample(DTA_PY118_BASE64), $opts), "limit");
    $opts.maxCells = 30;
    testing.assertEqual(readDta(dtaSample(DTA_H115_BASE64), $opts).rowCount, 5);
    $opts.maxCells = 0;
    testing.assertEqual(dtaKind(dtaSample(DTA_H115_BASE64), $opts), ERROR_KIND);
}

func testDtaTruncated() {
    # a tagged file is whole or malformed: every third length of one
    def tagged as bytes init dtaSample(DTA_PD119BE_BASE64);
    def cut as int init 0;
    while ($cut < len($tagged)) {
        testing.assertThrowsWith("dtaReadBytes", [binary.slice($tagged, 0, $cut)], ERROR_KIND);
        $cut = $cut + 3;
    }
    # an old file may end after its data or after any value label table
    def b as bytes init dtaSample(DTA_H108_BASE64);
    def whole as int init 0;
    for (def n in 0..len($b)) {
        try {
            def ds as Dataset init dtaReadBytes(binary.slice($b, 0, $n));
            testing.assertEqual(variable($ds, "a").valueLabels, {});
            $whole = $whole + 1;
        } catch (e) {
            testing.assertEqual($e.kind, ERROR_KIND);
        }
    }
    testing.assertEqual($whole, 1);
}

func testDtaCorruptBytes() {
    # every third byte of a file set to 0xff in turn: an error of the deck's kinds or a dataset
    def b as bytes init dtaSample(DTA_H115_BASE64);
    def i as int init 0;
    while ($i < len($b)) {
        $i = $i + 3;
        try {
            dtaReadBytes(dtaPatch($b, $i - 3, [255]));
        } catch (e) {
            testing.assertTrue($e.kind == ERROR_KIND or $e.kind == "limit");
        }
    }
}

func testDtaMalformed() {
    def old as bytes init dtaSample(DTA_H115_BASE64);
    # byte order 3, file type 2, an unknown type code, a never-released format
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 1, [3])], ERROR_KIND);
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 2, [2])], ERROR_KIND);
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 109, [250])], ERROR_KIND);
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 0, [116])], ERROR_KIND);
    # data at 1310, 24-byte records: a NaN float, a double above .z
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($old, 1317, [255, 255, 255, 127])],
        ERROR_KIND);
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($old, 1321, [0, 0, 0, 0, 0, 27, 224, 127])],
        ERROR_KIND);
    # the label table at 1430: n no longer matches its length; a text offset outside it
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 1470, [5])], ERROR_KIND);
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($old, 1478, [200])], ERROR_KIND);

    def tagged as bytes init dtaSample(DTA_PD118BE_BASE64);
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($tagged, dtaFind($tagged, "<release>") + 9, [49, 49, 54])],
        ERROR_KIND);
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($tagged, dtaFind($tagged, "<byteorder>") + 11, [88])],
        ERROR_KIND);
    # a GSO of type 131; a strL reference to (2,9), which no GSO defines
    def gso as int init dtaFind($tagged, "GSO");
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($tagged, $gso + 15, [131])], ERROR_KIND);
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($tagged, dtaFind($tagged, "<data>") + 6 + 15, [9])],
        ERROR_KIND);
    # a map entry that disagrees, a missing closing tag, a byte after the end
    def mapAt as int init dtaFind($tagged, "<map>") + 5;
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($tagged, $mapAt + 9 * 8 + 7, [1])],
        ERROR_KIND);
    testing.assertThrowsWith(
        "dtaReadBytes",
        [dtaPatch($tagged, dtaFind($tagged, "</data>") + 2, [120])],
        ERROR_KIND);
    testing.assertThrowsWith("dtaReadBytes", [binary.join([$tagged, binary.make(1)])], ERROR_KIND);
    # a map entry above the int range
    testing.assertThrowsWith("dtaReadBytes", [dtaPatch($tagged, $mapAt, [255])], ERROR_KIND);
}

func testDtaThroughReadAndCsv() {
    def ds as Dataset init read(dtaSample(DTA_PD118_BASE64));
    testing.assertEqual(
        toCsv($ds, true),
        "b,h,city,s\r\n-1,-300,Zürich,€uro\r\n0,0,Genève,ß\r\n100,300,Zürich,");
}
