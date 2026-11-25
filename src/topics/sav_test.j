# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# statfiles - white-box tests for the sav topic. Spliced into
# statfiles_test.j via include. Every expected value was checked against
# pyreadstat.read_sav(..., user_missing=True).

include "fixtures/sav_fixtures_test.j";

/**
 * A fixture as bytes.
 *
 * @param lines {list of string} its base64 lines
 * @return {bytes} the file
 */
func savFixture(lines as list of string) {
    return encoding.fromText("base64", strings.join($lines, ""));
}

/**
 * The kind of error reading a file throws, `""` if it reads.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {string} the error kind
 */
func savKind(data as bytes, opts as Options) {
    try {
        readSav($data, $opts);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * Options with a cell and byte cap.
 *
 * @param cells {int} `maxCells`
 * @param size {int} `maxBytes`
 * @return {Options} the options
 */
func savCaps(cells as int, size as int) {
    return Options{encoding: "", maxCells: $cells, maxBytes: $size};
}

/**
 * Throw unless two datasets hold the same variables and cells.
 *
 * @param a {Dataset} one
 * @param b {Dataset} the other
 */
func savSameCells(a as Dataset, b as Dataset) {
    testing.assertEqual($a.variables, $b.variables);
    testing.assertEqual($a.rowCount, $b.rowCount);
    testing.assertEqual($a.numbers, $b.numbers);
    testing.assertEqual($a.texts, $b.texts);
    testing.assertEqual($a.missing, $b.missing);
    testing.assertEqual($a.label, $b.label);
    testing.assertEqual($a.encoding, $b.encoding);
}

func testSavReadStatPlain() {
    def ds as Dataset init readSav(savFixture(SAV_READSTAT_PLAIN), options());
    testing.assertEqual($ds.format, "sav");
    testing.assertEqual($ds.version, "");
    testing.assertEqual($ds.label, "Test file äö");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(names($ds), ["id", "score", "respondentAge", "name", "longtext", "born"]);

    def id as Variable init variable($ds, "id");
    testing.assertEqual($id.label, "Identifier");
    testing.assertEqual($id.type, "numeric");
    testing.assertEqual($id.storage, "numeric");
    testing.assertEqual($id.width, 8);
    testing.assertEqual($id.format, "F8.2");
    testing.assertEqual($id.valueLabels, {"1": "one", "2": "two", "3.5": "three and a half"});
    testing.assertEqual(labelOf($ds, "id", 1), "two");

    testing.assertEqual($ds.numbers[1], [1.5, 0.0, 99.0, -2.25, 1e10]);
    testing.assertEqual($ds.missing[1], ["", ".", "user", "user", ""]);
    testing.assertEqual(variable($ds, "score").missingValues, ["99", "-2.25"]);
    testing.assertEqual(variable($ds, "score").missingRange, []);
    testing.assertEqual(number($ds, "score", 2), 99.0);

    testing.assertEqual(variable($ds, "respondentAge").missingRange, [900.0, 1000.0]);
    testing.assertEqual($ds.missing[2], ["", "user", "", "", ""]);

    def nm as Variable init variable($ds, "name");
    testing.assertEqual($nm.type, "string");
    testing.assertEqual($nm.width, 20);
    testing.assertEqual($nm.format, "A20");
    testing.assertEqual($nm.missingValues, ["Bob"]);
    testing.assertEqual($nm.valueLabels, {"Anna": "the first", "Bob": "B"});
    testing.assertEqual(
        textColumn($ds, "name"),
        ["Anna", "Bob", "Grüße", "", "xxxxxxxxxxxxxxxxxxxx"]);
    testing.assertEqual($ds.missing[3], ["", "user", "", "", ""]);
    testing.assertEqual($ds.numbers[3], []);

    def lt as Variable init variable($ds, "longtext");
    testing.assertEqual($lt.width, 300);
    testing.assertEqual($lt.format, "A300");
    testing.assertEqual($lt.label, "A very long string");
    testing.assertEqual($lt.valueLabels, {"short": "a short one"});
    def col as list of string init textColumn($ds, "longtext");
    testing.assertEqual($col[0], strings.replicate("a", 300));
    testing.assertEqual($col[1], strings.replicate("b", 260) + "end");
    testing.assertEqual($col[2], "short");
    testing.assertEqual($col[3], "");
    testing.assertEqual($col[4], strings.replicate("z", 290));

    testing.assertEqual(variable($ds, "born").format, "DATE11");
    testing.assertEqual(
        $ds.numbers[5],
        [12850617600.0, 13171161600.0, 0.0, 11935296000.0, 13939171200.0]);
    testing.assertEqual($ds.missing[5], ["", "", ".", "", ""]);
}

func testSavReadStatCompressed() {
    def plain as Dataset init readSav(savFixture(SAV_READSTAT_PLAIN), options());
    def bc as Dataset init readSav(savFixture(SAV_READSTAT_BYTECODE), options());
    def z as Dataset init readSav(savFixture(SAV_READSTAT_ZSAV), options());
    savSameCells($bc, $plain);
    savSameCells($z, $plain);
    testing.assertEqual($bc.format, "sav");
    testing.assertEqual($z.format, "zsav");
}

func testSavPspp() {
    def ds as Dataset init readSav(savFixture(SAV_PSPP_PLAIN), options());
    testing.assertEqual($ds.label, "PSPP made this");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 4);
    testing.assertEqual(names($ds), ["id", "x", "y", "zLongVariableName", "s", "t", "d"]);
    testing.assertEqual(variable($ds, "id").format, "F4.0");
    testing.assertEqual(variable($ds, "id").valueLabels, {"1": "one", "2": "two"});

    def x as Variable init variable($ds, "x");
    testing.assertEqual($x.label, "An x ±");
    testing.assertEqual($x.format, "F9.3");
    testing.assertEqual($x.missingRange, [LOWEST, -5.0]);
    testing.assertEqual($x.missingValues, ["99"]);
    testing.assertEqual($ds.numbers[1], [1.5, 0.0, -0.001, 123456.789]);
    testing.assertEqual($ds.missing[1], ["", ".", "", ""]);

    testing.assertEqual(variable($ds, "y").missingRange, [99.0, HIGHEST]);
    testing.assertEqual($ds.missing[2], ["", "user", "", "user"]);
    testing.assertEqual(variable($ds, "zLongVariableName").missingValues, ["1000", "15", "7"]);
    testing.assertEqual($ds.missing[3], ["", "user", "", "user"]);

    def s as Variable init variable($ds, "s");
    testing.assertEqual($s.width, 6);
    testing.assertEqual($s.missingValues, ["zz", "a b"]);
    testing.assertEqual($s.valueLabels, {"abc": "the abc"});
    testing.assertEqual($ds.texts[4], ["abc", "Gr????", "a b", "zz"]);
    testing.assertEqual($ds.missing[4], ["", "", "user", "user"]);

    def t as Variable init variable($ds, "t");
    testing.assertEqual($t.width, 300);
    testing.assertEqual($t.format, "A300");
    testing.assertEqual($t.missingValues, ["short", "x"]);
    testing.assertEqual($t.valueLabels, {"short": "very long label key"});
    testing.assertEqual(
        $ds.texts[5][1],
        "long" + strings.replicate("ab", 120) + "|" + strings.replicate("1234567890", 5));
    testing.assertEqual($ds.texts[5][2], "");
    testing.assertEqual($ds.missing[5], ["user", "", "", ""]);

    testing.assertEqual(variable($ds, "d").format, "DATE11");
    testing.assertEqual($ds.missing[6], ["", "", ".", ""]);
}

func testSavPsppCompressed() {
    def plain as Dataset init readSav(savFixture(SAV_PSPP_PLAIN), options());
    def bc as Dataset init readSav(savFixture(SAV_PSPP_BYTECODE), options());
    def z as Dataset init readSav(savFixture(SAV_PSPP_ZSAV), options());
    savSameCells($bc, $plain);
    savSameCells($z, $plain);
    testing.assertEqual($z.format, "zsav");
}

func testSavBigEndianCodePage() {
    def ds as Dataset init readSav(savFixture(SAV_HAND_BE), options());
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.label, "Café file");
    testing.assertEqual(names($ds), ["NUM", "COUNT", "TXT"]);
    def num as Variable init variable($ds, "NUM");
    testing.assertEqual($num.label, "Número");
    testing.assertEqual($num.valueLabels, {"1": "one", "-1": "refusé"});
    testing.assertEqual($num.missingValues, ["-1"]);
    testing.assertEqual($ds.numbers[0], [1.0, -1.0, 0.0, 2.75]);
    testing.assertEqual($ds.missing[0], ["", "user", ".", ""]);
    testing.assertEqual(variable($ds, "COUNT").format, "F5.0");
    testing.assertEqual($ds.numbers[1], [3.0, 0.0, 12.5, 0.0]);
    testing.assertEqual($ds.missing[1], ["", "", "", "."]);
    testing.assertEqual(variable($ds, "TXT").width, 10);
    testing.assertEqual($ds.texts[2], ["Café", "", "abcdefghij", "x"]);
}

func testSavUnknownCaseCount() {
    def plain as Dataset init readSav(savFixture(SAV_HAND_BE), options());
    savSameCells(readSav(savFixture(SAV_HAND_BE_BYTECODE), options()), $plain);
    savSameCells(readSav(savFixture(SAV_HAND_LE_BYTECODE), options()), $plain);
    testing.assertEqual(
        savKind(savFixture(SAV_HAND_LE_BYTECODE), savCaps(12, DEFAULT_MAX_BYTES)),
        "");
    testing.assertEqual(
        savKind(savFixture(SAV_HAND_LE_BYTECODE), savCaps(11, DEFAULT_MAX_BYTES)),
        "limit");
}

func testSavEncodingOption() {
    def opts as Options init options();
    $opts.encoding = "windows-1252";
    def ds as Dataset init readWith(savFixture(SAV_READSTAT_PLAIN), $opts);
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.texts[3][2], "GrÃ¼ÃŸe");
    $opts.encoding = "no-such-charset";
    testing.assertEqual(savKind(savFixture(SAV_READSTAT_PLAIN), $opts), "statfiles");
}

func testSavDetectAndRead() {
    testing.assertEqual(detect(savFixture(SAV_READSTAT_PLAIN)), "sav");
    testing.assertEqual(detect(savFixture(SAV_PSPP_ZSAV)), "zsav");
    testing.assertTrue(looksLikeSav(savFixture(SAV_HAND_BE)));
    testing.assertFalse(looksLikeSav(encoding.encode("utf-8", "$FL")));
    testing.assertEqual(read(savFixture(SAV_PSPP_BYTECODE)).rowCount, 4);
    testing.assertTrue(strings.startsWith(
        toCsv(read(savFixture(SAV_HAND_BE)), true),
        "NUM,COUNT,TXT\r\none,3,Café\r\n"));
}

func testSavCaps() {
    def plain as bytes init savFixture(SAV_READSTAT_PLAIN);
    testing.assertEqual(savKind($plain, savCaps(30, DEFAULT_MAX_BYTES)), "");
    testing.assertEqual(savKind($plain, savCaps(29, DEFAULT_MAX_BYTES)), "limit");
    testing.assertEqual(
        savKind(savFixture(SAV_READSTAT_BYTECODE), savCaps(29, DEFAULT_MAX_BYTES)),
        "limit");
    testing.assertEqual(savKind($plain, savCaps(0, DEFAULT_MAX_BYTES)), "statfiles");
    # the PSPP .zsav: 880 bytes of bytecode in its zlib blocks, which unpack
    # to 4 cases of 44 slots, 1408 bytes
    def z as bytes init savFixture(SAV_PSPP_ZSAV);
    testing.assertEqual(savKind($z, savCaps(DEFAULT_MAX_CELLS, 1408)), "");
    testing.assertEqual(savKind($z, savCaps(DEFAULT_MAX_CELLS, 879)), "limit");
}

# maxBytes also caps what the bytecode unpacks to: one code byte stands for 8
# bytes, so a tiny file of blank long strings would otherwise unpack to far
# more than maxBytes (and a .zsav of them compresses a thousandfold first).
func testSavBytecodeUnpacksWithinMaxBytes() {
    for (def lines in [SAV_PSPP_ZSAV, SAV_PSPP_BYTECODE]) {
        def data as bytes init savFixture($lines);
        testing.assertEqual(savKind($data, savCaps(DEFAULT_MAX_CELLS, 1408)), "");
        testing.assertEqual(savKind($data, savCaps(DEFAULT_MAX_CELLS, 1407)), "limit");
    }
    # cases = -1 (unknown): the rows are counted against the cap as they unpack
    def unknown as bytes init savFixture(SAV_PSPP_BYTECODE);
    for (def k in 80..84) {
        $unknown[$k] = 255;
    }
    testing.assertEqual(savKind($unknown, savCaps(DEFAULT_MAX_CELLS, 1408)), "");
    testing.assertEqual(savKind($unknown, savCaps(DEFAULT_MAX_CELLS, 1407)), "limit");
}

func testSavTruncated() {
    for (def lines in [
        SAV_READSTAT_PLAIN,
        SAV_READSTAT_BYTECODE,
        SAV_READSTAT_ZSAV,
        SAV_PSPP_PLAIN,
        SAV_PSPP_BYTECODE,
        SAV_PSPP_ZSAV,
        SAV_HAND_BE
    ]) {
        def data as bytes init savFixture($lines);
        for (def n in 0..len($data)) {
            if ($n % 41 == 0 or $n > len($data) - 16) {
                testing.assertEqual(savKind($data[..$n], options()), "statfiles");
            }
        }
    }
}

func testSavMalformed() {
    def data as bytes init savFixture(SAV_HAND_BE);
    def bad as bytes init $data;
    $bad[3] = 57;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    $bad = $data;
    $bad[67] = 9;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    $bad = $data;
    $bad[75] = 7;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    $bad = $data;
    $bad[179] = 5;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    $bad = $data;
    $bad[] = 0;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    def z as bytes init savFixture(SAV_PSPP_ZSAV);
    $bad = $z;
    $bad[len($z) - 100] = $z[len($z) - 100] ^ 255;
    testing.assertEqual(savKind($bad, options()), "statfiles");
    $bad = binary.concat($z, binary.make(1));
    testing.assertEqual(savKind($bad, options()), "statfiles");
}

func testSavCorruptBytes() {
    def data as bytes init savFixture(SAV_HAND_LE_BYTECODE);
    for (def p in 0..len($data)) {
        for (def v in [0, 255, 253]) {
            def bad as bytes init $data;
            $bad[$p] = $v;
            def kind as string init savKind($bad, options());
            testing.assertTrue($kind == "" or $kind == "statfiles" or $kind == "limit");
        }
    }
}

func testSavEncodeFloat() {
    for (def x in [1.0, -99.0, 151.0, 0.5, LOWEST, HIGHEST, 2.2250738585072014e-308]) {
        testing.assertEqual(binary.readFloat("le", savEncodeFloat($x, "le"), 0, 8), $x);
        testing.assertEqual(binary.readFloat("be", savEncodeFloat($x, "be"), 0, 8), $x);
    }
    testing.assertEqual(savFormatOf(5, 8, 2), "F8.2");
    testing.assertEqual(savFormatOf(1, 20, 0), "A20");
    testing.assertEqual(savFormatOf(20, 11, 0), "DATE11");
    testing.assertEqual(savFormatOf(3, 9, 0), "COMMA9");
    testing.assertEqual(savFormatOf(0, 0, 0), "");
}
