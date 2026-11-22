# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# statfiles - white-box tests for the por topic. Spliced into
# statfiles_test.j via include. The values were checked against
# pyreadstat.read_por, which reads user-missing values as missing.

include "fixtures/por_fixtures_test.j";

/**
 * A fixture as bytes.
 *
 * @param lines {list of string} its base64 lines
 * @return {bytes} the file
 */
func porFixture(lines as list of string) {
    return encoding.fromText("base64", strings.join($lines, ""));
}

/**
 * The kind of error reading a file throws, `""` if it reads.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {string} the error kind
 */
func porKind(data as bytes, opts as Options) {
    try {
        readPor($data, $opts);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * The number a base-30 text reads as.
 *
 * @param text {string} the text
 * @return {PorCursor} the cursor after it
 */
func porParse(text as string) {
    def c as PorCursor init PorCursor{pos: 0, num: 0.0, sysmis: false};
    return porNumber(encoding.encode("utf-8", $text), $c);
}

/**
 * The kind of error a base-30 text throws, `""` if it reads.
 *
 * @param text {string} the text
 * @return {string} the error kind
 */
func porParseKind(text as string) {
    try {
        porParse($text);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

func testPorNumbers() {
    testing.assertEqual(porParse("1.F/").num, 1.5);
    testing.assertEqual(porParse("-2.7F/").num, -2.25);
    testing.assertEqual(porParse("  14/").num, 34.0);
    testing.assertEqual(porParse("139/").num, 999.0);
    testing.assertEqual(porParse("-R-3/").num, -0.001);
    testing.assertEqual(porParse(".F/").num, 0.5);
    testing.assertEqual(porParse("1+2/").num, 900.0);
    testing.assertEqual(porParse("A9E17IR6IG+6J/").num, HIGHEST);
    testing.assertTrue(porParse("*.").sysmis);
    testing.assertEqual(porParse("*.").pos, 2);
    testing.assertEqual(porParse("1.F/").pos, 4);
    for (def bad in ["1.F", "/", "-/", "*/", "1+/", "U/", "1..2/", "1+ZZ/", "1+TTTT/", "1+11111/"]) {
        testing.assertEqual(porParseKind($bad), "statfiles");
    }
}

# Base-30 numbers as ReadStat writes doubles (12 digits) and longer ones read
# as the nearest float, not one or two ulp off.
func testPorNumbersRoundCorrectly() {
    testing.assertEqual(porParse("11EP9.D5H0GIP/").num, 850359.4395192028);
    testing.assertEqual(porParse("3O2RSJTPOLCN+A/").num, 3.978341795374614e31);
    testing.assertEqual(porParse("IJ5ET4J9HE4L-5F/").num, 6.219560729721658e-227);
    testing.assertEqual(porParse(".3333333333333333333333/").num, 0.10344827586206896);
    testing.assertEqual(porParse("-1234567890ABCDEFGHIJ.KLMNOPQRST/").num, -1.2437994296070175e28);
}

func testPorReadStat() {
    def ds as Dataset init readPor(porFixture(POR_READSTAT), options());
    testing.assertEqual($ds.format, "por");
    testing.assertEqual($ds.version, "");
    testing.assertEqual($ds.label, "Test file");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(names($ds), ["ID", "SCORE", "AGE", "NAME", "BORN"]);
    testing.assertEqual(variable($ds, "SCORE").format, "F8.2");
    # a text format: a number has no byte width
    testing.assertEqual(variable($ds, "SCORE").width, 0);
    testing.assertEqual($ds.numbers[1], [1.5, 0.0, 99.0, -2.25, 1e10]);
    testing.assertEqual($ds.missing[1], ["", ".", "", "", ""]);
    testing.assertEqual($ds.numbers[2], [34.0, 999.0, 12.0, 5.0, 70.0]);
    testing.assertEqual(variable($ds, "NAME").width, 20);
    testing.assertEqual(variable($ds, "NAME").format, "A20");
    testing.assertEqual($ds.texts[3], ["Anna", "Bob", "Gruss", "", "xxxxxxxxxxxxxxxxxxxx"]);
    testing.assertEqual($ds.missing[3], ["", "", "", "", ""]);
    testing.assertEqual(variable($ds, "BORN").format, "DATE11");
    testing.assertEqual(
        $ds.numbers[4],
        [12850617600.0, 13171161600.0, 0.0, 11935296000.0, 13939171200.0]);
}

func testPorPspp() {
    def ds as Dataset init readPor(porFixture(POR_PSPP), options());
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.rowCount, 4);
    testing.assertEqual(names($ds), ["ID", "X", "Y", "ZLONGVAR", "S", "T", "D"]);
    testing.assertEqual(variable($ds, "ID").label, "Identifier");
    testing.assertEqual(variable($ds, "ID").valueLabels, {"1": "one", "2": "two"});
    testing.assertEqual(variable($ds, "ID").format, "F4.0");

    def x as Variable init variable($ds, "X");
    testing.assertEqual($x.label, "An x ±");
    testing.assertEqual($x.missingRange, [LOWEST, -5.0]);
    testing.assertEqual($x.missingValues, ["99"]);
    testing.assertEqual($ds.numbers[1], [1.5, 0.0, -0.001, 123456.789]);
    testing.assertEqual($ds.missing[1], ["", ".", "", ""]);

    # PSPP writes `99 THRU HI` as an `A` record holding HI, not 99
    testing.assertEqual(variable($ds, "Y").missingRange, [HIGHEST, HIGHEST]);
    testing.assertEqual($ds.missing[2], ["", "", "", ""]);

    testing.assertEqual(variable($ds, "ZLONGVAR").missingValues, ["1000", "15", "7"]);
    testing.assertEqual($ds.missing[3], ["", "user", "", "user"]);

    def s as Variable init variable($ds, "S");
    testing.assertEqual($s.width, 6);
    testing.assertEqual($s.label, "String var");
    testing.assertEqual($s.missingValues, ["zz", "a b"]);
    testing.assertEqual($s.valueLabels, {"abc": "the abc"});
    testing.assertEqual($ds.texts[4], ["abc", "Gr????", "a b", "zz"]);
    testing.assertEqual($ds.missing[4], ["", "", "user", "user"]);

    def t as Variable init variable($ds, "T");
    testing.assertEqual($t.width, 255);
    testing.assertEqual($t.format, "A255");
    testing.assertEqual($t.valueLabels, {"short": "very long label key"});
    testing.assertEqual($t.missingValues, ["short", "x"]);
    testing.assertEqual(
        $ds.texts[5][1],
        "long" + strings.replicate("ab", 120) + "|" + strings.replicate("1234567890", 1));
    testing.assertEqual($ds.missing[5], ["user", "", "", ""]);
    testing.assertEqual($ds.missing[6], ["", "", ".", ""]);
}

func testPorTranslated() {
    def a as Dataset init readPor(porFixture(POR_PSPP), options());
    def b as Dataset init readPor(porFixture(POR_SWAPPED), options());
    testing.assertEqual($b.variables, $a.variables);
    testing.assertEqual($b.numbers, $a.numbers);
    testing.assertEqual($b.texts, $a.texts);
    testing.assertEqual($b.missing, $a.missing);
}

func testPorDetectAndRead() {
    testing.assertEqual(detect(porFixture(POR_READSTAT)), "por");
    testing.assertEqual(detect(porFixture(POR_SWAPPED)), "por");
    testing.assertTrue(looksLikePor(porFixture(POR_PSPP)));
    testing.assertFalse(looksLikePor(binary.make(600, 48)));
    testing.assertFalse(looksLikePor(binary.make(10, 10)));
    testing.assertEqual(read(porFixture(POR_PSPP)).rowCount, 4);
}

func testPorEncodingOption() {
    def opts as Options init options();
    $opts.encoding = "windows-1252";
    def ds as Dataset init readPor(porFixture(POR_PSPP), $opts);
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual(variable($ds, "X").label, "An x Â±");
}

func testPorCaps() {
    def data as bytes init porFixture(POR_READSTAT);
    testing.assertEqual(porKind($data, Options{encoding: "", maxCells: 25, maxBytes: 1}), "");
    testing.assertEqual(porKind($data, Options{encoding: "", maxCells: 24, maxBytes: 1}), "limit");
    testing.assertEqual(
        porKind($data, Options{encoding: "", maxCells: 0, maxBytes: 1}),
        "statfiles");
}

func testPorTruncated() {
    for (def lines in [POR_READSTAT, POR_PSPP, POR_SWAPPED]) {
        def data as bytes init porFixture($lines);
        for (def n in 0..len($data) - 82) {
            if ($n % 23 == 0) {
                testing.assertEqual(porKind($data[..$n], options()), "statfiles");
            }
        }
    }
}

func testPorMalformed() {
    def data as bytes init porFixture(POR_READSTAT);
    def bad as bytes init $data;
    # SPSSPORT starts at byte 466: 456 plus the five line ends before it
    $bad[470] = 88;
    testing.assertEqual(porKind($bad, options()), "statfiles");
    $bad = binary.concat(binary.make(81, 32), $data);
    testing.assertEqual(porKind($bad, options()), "statfiles");
    $bad = binary.concat($data, encoding.encode("utf-8", "1/"));
    testing.assertEqual(porKind($bad, options()), "statfiles");
    for (def p in POR_RECORDS_AT..len($data)) {
        if ($p % 3 == 0) {
            for (def v in [90, 42, 47, 45, 70]) {
                def b2 as bytes init $data;
                $b2[$p] = $v;
                def kind as string init porKind($b2, options());
                testing.assertTrue($kind == "" or $kind == "statfiles" or $kind == "limit");
            }
        }
    }
}
