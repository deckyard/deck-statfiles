# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - white-box tests for the dataset topic. Spliced into
# statfiles_test.j via include.

/**
 * A small dataset built by hand: a numeric variable with a value label, a
 * user-missing value and a Stata-style missing code, and a string variable.
 *
 * @return {Dataset} the dataset
 */
func handMade() {
    return Dataset{
        format: "sav",
        version: "",
        name: "",
        label: "probe",
        encoding: "utf-8",
        rowCount: 4,
        variables: [
            Variable{
                name: "age",
                label: "Age in years",
                type: "numeric",
                storage: "numeric",
                width: 0,
                format: "F3.0",
                valueLabels: {"99": "refused"},
                missingValues: ["99"],
                missingRange: []
            },
            Variable{
                name: "town",
                label: "",
                type: "string",
                storage: "string",
                width: 8,
                format: "A8",
                valueLabels: {"Graz": "the capital of Styria"},
                missingValues: [],
                missingRange: []
            }
        ],
        numbers: [[34.0, 99.0, 0.0, 2.5], []],
        texts: [[], ["Graz", "Wien, 1", "", "a \"b\""]],
        missing: [["", "user", ".a", ""], ["", "", "", ""]]
    };
}

/** Fail a test whose call did not throw. */
func missed() {
    throw Error{kind: "test", message: "the call did not fail"};
}

func testValueKey() {
    testing.assertEqual(valueKey(3.0), "3");
    testing.assertEqual(valueKey(-1.0), "-1");
    testing.assertEqual(valueKey(0.0), "0");
    testing.assertEqual(valueKey(2.5), "2.5");
    testing.assertEqual(valueKey(1e20), "1e+20");
}

func testColumnsAndCells() {
    def ds as Dataset init handMade();
    testing.assertEqual(names($ds), ["age", "town"]);
    testing.assertEqual(indexOf($ds, "town"), 1);
    testing.assertEqual(indexOf($ds, "Town"), -1);
    testing.assertEqual(variable($ds, "age").label, "Age in years");
    testing.assertEqual(present($ds, "age"), [34.0, 2.5]);
    testing.assertEqual(textColumn($ds, "town")[1], "Wien, 1");
    testing.assertEqual(missingCode($ds, "age", 2), ".a");
    testing.assertTrue(isMissing($ds, "age", 1));
    testing.assertFalse(isMissing($ds, "age", 0));
    testing.assertEqual(number($ds, "age", 1), 99.0);
    testing.assertEqual(text($ds, "age", 1), "99");
    testing.assertEqual(text($ds, "age", 2), ".a");
    testing.assertEqual(text($ds, "town", 0), "Graz");
    testing.assertEqual(labelOf($ds, "age", 1), "refused");
    testing.assertEqual(labelOf($ds, "age", 0), "");
    testing.assertEqual(labelOf($ds, "town", 0), "the capital of Styria");
    try {
        column($ds, "age");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        number($ds, "age", 2);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        column($ds, "town");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        textColumn($ds, "age");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        variable($ds, "nope");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        text($ds, "age", 4);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        text($ds, "age", -1);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    $ds.missing[0] = ["", "", "", ""];
    testing.assertEqual(column($ds, "age"), [34.0, 99.0, 0.0, 2.5]);
}

func testToCsv() {
    def ds as Dataset init handMade();
    testing.assertEqual(
        toCsv($ds, false),
        "age,town\r\n34,Graz\r\n99,\"Wien, 1\"\r\n,\r\n2.5,\"a \"\"b\"\"\"");
    testing.assertEqual(
        toCsv($ds, true),
        "age,town\r\n34,the capital of Styria\r\nrefused,\"Wien, 1\"\r\n,\r\n2.5,\"a \"\"b\"\"\"");
    $ds.rowCount = 0;
    $ds.numbers = [[], []];
    $ds.texts = [[], []];
    $ds.missing = [[], []];
    testing.assertEqual(toCsv($ds, false), "age,town");
    testing.assertEqual(present($ds, "age"), []);
}

func testCharsetNames() {
    testing.assertEqual(charsetName("UTF-8"), "utf-8");
    testing.assertEqual(charsetName("CP1252"), "windows-1252");
    testing.assertEqual(charsetName("windows-1250"), "windows-1250");
    testing.assertEqual(charsetName("ISO-8859-15"), "iso-8859-15");
    testing.assertEqual(charsetName("ISO8859_2"), "iso-8859-2");
    testing.assertEqual(charsetName("latin1"), "iso-8859-1");
    testing.assertEqual(charsetName("US-ASCII"), "ascii");
    try {
        charsetName("shift_jis");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

# A name of the ISO 8859 pattern that no codec has (there is no part 12) is
# refused up front, not passed on to fail later as a byte it "lacks".
func testCharsetNamesRefuseMissingCodecs() {
    for (def name in ["ISO-8859-12", "iso8859-0", "iso-8859-99"]) {
        try {
            charsetName($name);
            missed();
        } catch (e) {
            testing.assertEqual($e.kind, ERROR_KIND);
        }
    }
}

func testDecodeText() {
    def b as bytes init convert.bytesFromString("utf-8", "Grün  ");
    $b[] = 0;
    $b[] = 0;
    testing.assertEqual(decodeText($b, "utf-8"), "Grün");
    testing.assertEqual(decodeText(encoding.encode("windows-1252", "été "), "windows-1252"), "été");
    testing.assertEqual(decodeText(binary.make(4), "utf-8"), "");
    try {
        decodeText(encoding.encode("windows-1252", "é"), "utf-8");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testDecodeTextRefusesBytesTheCharsetLacks() {
    def b as bytes init binary.make(1, 129);
    try {
        decodeText($b, "windows-1252");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        decodeText($b, "ascii");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testReadRefusesUnknownData() {
    testing.assertEqual(detect(convert.bytesFromString("utf-8", "hello")), "");
    testing.assertEqual(detect(convert.bytesFromString("utf-8", "$FL2...")), "sav");
    testing.assertEqual(detect(convert.bytesFromString("utf-8", "$FL3...")), "zsav");
    try {
        read(convert.bytesFromString("utf-8", "hello"));
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testCheckSize() {
    checkSize(options(), 1000, 1000);
    def small as Options init options();
    $small.maxCells = 10;
    try {
        checkSize($small, 6, 2);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    checkSize($small, 5, 2);
    checkSize($small, 100, 0);
    $small.maxCells = 0;
    try {
        checkSize($small, 1, 1);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}
