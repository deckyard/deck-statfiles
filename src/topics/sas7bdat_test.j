# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - white-box tests for the sas7bdat topic. Spliced into
# statfiles_test.j via include. The expected values of the testSas7<sample>
# tests were taken from pyreadstat 1.3.8 (ReadStat); every cell of every
# sample was also compared with pyreadstat and pandas outside the deck.

include "fixtures/sas7files_test.j";

/**
 * A sample file from its gzip-compressed base64 lines.
 *
 * @param lines {list of string} one of the SAS7_FILE_* / SAS7_CATALOG_* constants
 * @return {bytes} the file
 */
func sas7Fixture(lines as list of string) {
    return compress.unpack("gzip", encoding.fromText("base64", strings.join($lines, "")));
}

/**
 * Read a sample data set with the default options.
 *
 * @param lines {list of string} the sample
 * @return {Dataset} the data set
 */
func sas7Read(lines as list of string) {
    return readSas7bdat(sas7Fixture($lines), options());
}

/**
 * The kind of the error reading a data set throws, `""` when it reads.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {string} the kind
 */
func sas7ErrorKind(data as bytes, opts as Options) {
    try {
        readSas7bdat($data, $opts);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * The message of the error reading a data set throws, `""` when it reads.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {string} the message
 */
func sas7ErrorMessage(data as bytes, opts as Options) {
    try {
        readSas7bdat($data, $opts);
    } catch (e) {
        return $e.message;
    }
    return "";
}

/**
 * A copy of a file with bytes written over it.
 *
 * @param data {bytes} the file
 * @param at {int} the first byte to replace
 * @param values {list of int} the new bytes
 * @return {bytes} the patched copy
 */
func sas7Patch(data as bytes, at as int, values as list of int) {
    for (def i in 0..len($values)) {
        $data[$at + $i] = $values[$i];
    }
    return $data;
}

/**
 * The offset of the first plain subheader of a kind.
 *
 * @param data {bytes} the file
 * @param kind {int} a SAS7_SH_* kind
 * @return {int} its offset, -1 if there is none
 */
func sas7Locate(data as bytes, kind as int) {
    def pages as Sas7Pages init sas7Pages($data, sas7Head($data, options()));
    for (def i in 0..len($pages.ptrKinds)) {
        if ($pages.ptrComps[$i] == SAS7_COMP_NONE and $pages.ptrKinds[$i] == $kind) {
            return $pages.ptrOffsets[$i];
        }
    }
    return -1;
}

/**
 * The columns the sample checks look at: the first 16 and the last.
 *
 * @param ds {Dataset} the data set
 * @return {list of int} the variable indexes
 */
func sas7CheckedColumns(ds as Dataset) {
    def n as int init len($ds.variables);
    def out as list of int init [];
    for (def i in 0..math.min($n, 16)) {
        $out[] = $i;
    }
    if ($n > 16) {
        $out[] = $n - 1;
    }
    return $out;
}

/**
 * Compare one property of the checked variables.
 *
 * @param ds {Dataset} the data set
 * @param what {string} `names`, `labels`, `formats`, `types` or `widths`
 * @param want {list of string} the expected values
 */
func sas7ExpectVariables(ds as Dataset, what as string, want as list of string) {
    def got as list of string init [];
    for (def i in sas7CheckedColumns($ds)) {
        def v as Variable init $ds.variables[$i];
        if ($what == "names") {
            $got[] = $v.name;
        } elseif ($what == "labels") {
            $got[] = $v.label;
        } elseif ($what == "formats") {
            $got[] = $v.format;
        } elseif ($what == "types") {
            $got[] = $v.type;
            testing.assertEqual($v.storage, $v.type);
        } else {
            $got[] = convert.toString($v.width);
        }
    }
    testing.assertEqual($got, $want);
}

/**
 * Compare the checked cells of one row: `n:<number>`, `s:<text>` or
 * `m:<missing code>`.
 *
 * @param ds {Dataset} the data set
 * @param row {int} the row
 * @param want {list of string} the expected cells
 */
func sas7ExpectRow(ds as Dataset, row as int, want as list of string) {
    def k as int init 0;
    for (def i in sas7CheckedColumns($ds)) {
        def cell as string init $want[$k];
        def kind as string init $cell[0..2];
        def value as string init $cell[2..];
        if ($kind == "s:") {
            testing.assertEqual($ds.texts[$i][$row], $value);
            testing.assertEqual($ds.missing[$i][$row], "");
        } elseif ($kind == "m:") {
            testing.assertEqual($ds.missing[$i][$row], $value);
            testing.assertEqual($ds.numbers[$i][$row], 0.0);
        } else {
            testing.assertEqual($ds.missing[$i][$row], "");
            testing.assertEqual($ds.numbers[$i][$row], convert.toFloat($value));
        }
        $k = $k + 1;
    }
}

/**
 * Compare how often each missing code occurs in the whole data set.
 *
 * @param ds {Dataset} the data set
 * @param codes {list of string} the codes, sorted
 * @param counts {list of int} how often each occurs
 */
func sas7ExpectMissing(ds as Dataset, codes as list of string, counts as list of int) {
    def seen as map of string to int init {};
    for (def col in $ds.missing) {
        for (def code in $col) {
            if ($code == "") {
                continue;
            }
            if (not maps.has($seen, $code)) {
                $seen[$code] = 0;
            }
            $seen[$code] = $seen[$code] + 1;
        }
    }
    testing.assertEqual(lists.sort(maps.keys($seen)), $codes);
    for (def i in 0..len($codes)) {
        testing.assertEqual($seen[$codes[$i]], $counts[$i]);
    }
}

func testSas7Cars() {
    def ds as Dataset init sas7Read(SAS7_FILE_CARS);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0000M0");
    testing.assertEqual($ds.name, "CARS");
    testing.assertEqual($ds.label, "Written by SAS");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 392);
    testing.assertEqual(len($ds.variables), 4);
    sas7ExpectVariables($ds, "names", ["MPG", "CYL", "ENG", "WGT"]);
    sas7ExpectVariables(
        $ds,
        "labels",
        [
            "miles per gallon",
            "number of cylinders",
            "engine displacement in cubic inches",
            "vehicle weight in pounds"
        ]);
    sas7ExpectVariables($ds, "formats", ["", "", "", ""]);
    sas7ExpectVariables($ds, "types", ["numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["8", "3", "8", "4"]);
    sas7ExpectRow($ds, 0, ["n:18.0", "n:8.0", "n:307.0", "n:3504.0"]);
    sas7ExpectRow($ds, 196, ["n:33.0", "n:4.0", "n:91.0", "n:1795.0"]);
    sas7ExpectRow($ds, 391, ["n:31.0", "n:4.0", "n:119.0", "n:2720.0"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7BigEndianRle() {
    def ds as Dataset init sas7Read(SAS7_FILE_TEST12);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M1");
    testing.assertEqual($ds.name, "TEST12");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual($ds.rowCount, 10);
    testing.assertEqual(len($ds.variables), 100);
    sas7ExpectVariables(
        $ds,
        "names",
        [
            "Column1",
            "Column2",
            "Column3",
            "Column4",
            "Column5",
            "Column6",
            "Column7",
            "Column8",
            "Column9",
            "Column10",
            "Column11",
            "Column12",
            "Column13",
            "Column14",
            "Column15",
            "Column16",
            "Column100"
        ]);
    sas7ExpectVariables(
        $ds,
        "labels",
        ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "formats",
        [
            "BEST12.",
            "$9.",
            "BEST12.",
            "MMDDYY10.",
            "BEST12.",
            "$9.",
            "BEST12.",
            "BEST12.",
            "BEST12.",
            "$9.",
            "BEST12.",
            "MMDDYY10.",
            "BEST12.",
            "$5.",
            "BEST12.",
            "BEST12.",
            "BEST12."
        ]);
    sas7ExpectVariables(
        $ds,
        "types",
        [
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric"
        ]);
    sas7ExpectVariables(
        $ds,
        "widths",
        ["8", "9", "8", "8", "8", "9", "8", "8", "8", "9", "8", "8", "8", "5", "8", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        [
            "n:0.636",
            "s:pear",
            "n:84.0",
            "n:2170.0",
            "n:0.103",
            "s:apple",
            "n:20.0",
            "m:.",
            "n:0.621",
            "s:apple",
            "m:.",
            "n:9697.0",
            "n:0.047",
            "s:dog",
            "n:7.0",
            "n:2543.0",
            "n:3230.0"
        ]);
    sas7ExpectRow(
        $ds,
        1,
        [
            "n:0.283",
            "s:dog",
            "n:49.0",
            "n:6275.0",
            "n:0.398",
            "s:pear",
            "n:50.0",
            "n:339.0",
            "n:0.561",
            "s:apple",
            "n:22.0",
            "n:8596.0",
            "n:0.661",
            "s:pear",
            "n:38.0",
            "n:4928.0",
            "n:4904.0"
        ]);
    sas7ExpectRow(
        $ds,
        2,
        [
            "n:0.452",
            "s:pear",
            "n:35.0",
            "n:8627.0",
            "n:0.117",
            "s:pear",
            "n:70.0",
            "n:5704.0",
            "n:0.209",
            "s:apple",
            "n:7.0",
            "n:5079.0",
            "n:0.961",
            "s:pear",
            "n:73.0",
            "m:.",
            "m:."
        ]);
    sas7ExpectRow(
        $ds,
        5,
        [
            "n:0.948",
            "s:dog",
            "n:33.0",
            "n:8962.0",
            "n:0.691",
            "s:pear",
            "m:.",
            "n:2276.0",
            "n:0.33",
            "s:crocodile",
            "n:27.0",
            "n:1104.0",
            "n:0.668",
            "s:",
            "n:73.0",
            "n:2883.0",
            "n:6088.0"
        ]);
    sas7ExpectRow(
        $ds,
        9,
        [
            "n:0.663",
            "s:pear",
            "m:.",
            "n:7735.0",
            "n:0.086",
            "s:apple",
            "n:80.0",
            "m:.",
            "m:.",
            "s:pear",
            "n:16.0",
            "n:9159.0",
            "n:0.053",
            "s:dog",
            "n:52.0",
            "n:3478.0",
            "m:."
        ]);
    sas7ExpectMissing($ds, ["."], [72]);
}

func testSas7BigEndian64() {
    def ds as Dataset init sas7Read(SAS7_FILE_TEST13);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M1");
    testing.assertEqual($ds.name, "TEST13");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual($ds.rowCount, 10);
    testing.assertEqual(len($ds.variables), 100);
    sas7ExpectVariables(
        $ds,
        "names",
        [
            "Column1",
            "Column2",
            "Column3",
            "Column4",
            "Column5",
            "Column6",
            "Column7",
            "Column8",
            "Column9",
            "Column10",
            "Column11",
            "Column12",
            "Column13",
            "Column14",
            "Column15",
            "Column16",
            "Column100"
        ]);
    sas7ExpectVariables(
        $ds,
        "labels",
        ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "formats",
        [
            "BEST12.",
            "$9.",
            "BEST12.",
            "MMDDYY10.",
            "BEST12.",
            "$9.",
            "BEST12.",
            "BEST12.",
            "BEST12.",
            "$9.",
            "BEST12.",
            "MMDDYY10.",
            "BEST12.",
            "$5.",
            "BEST12.",
            "BEST12.",
            "BEST12."
        ]);
    sas7ExpectVariables(
        $ds,
        "types",
        [
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "numeric",
            "numeric",
            "numeric"
        ]);
    sas7ExpectVariables(
        $ds,
        "widths",
        ["8", "9", "8", "8", "8", "9", "8", "8", "8", "9", "8", "8", "8", "5", "8", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        [
            "n:0.636",
            "s:pear",
            "n:84.0",
            "n:2170.0",
            "n:0.103",
            "s:apple",
            "n:20.0",
            "m:.",
            "n:0.621",
            "s:apple",
            "m:.",
            "n:9697.0",
            "n:0.047",
            "s:dog",
            "n:7.0",
            "n:2543.0",
            "n:3230.0"
        ]);
    sas7ExpectRow(
        $ds,
        1,
        [
            "n:0.283",
            "s:dog",
            "n:49.0",
            "n:6275.0",
            "n:0.398",
            "s:pear",
            "n:50.0",
            "n:339.0",
            "n:0.561",
            "s:apple",
            "n:22.0",
            "n:8596.0",
            "n:0.661",
            "s:pear",
            "n:38.0",
            "n:4928.0",
            "n:4904.0"
        ]);
    sas7ExpectRow(
        $ds,
        2,
        [
            "n:0.452",
            "s:pear",
            "n:35.0",
            "n:8627.0",
            "n:0.117",
            "s:pear",
            "n:70.0",
            "n:5704.0",
            "n:0.209",
            "s:apple",
            "n:7.0",
            "n:5079.0",
            "n:0.961",
            "s:pear",
            "n:73.0",
            "m:.",
            "m:."
        ]);
    sas7ExpectRow(
        $ds,
        5,
        [
            "n:0.948",
            "s:dog",
            "n:33.0",
            "n:8962.0",
            "n:0.691",
            "s:pear",
            "m:.",
            "n:2276.0",
            "n:0.33",
            "s:crocodile",
            "n:27.0",
            "n:1104.0",
            "n:0.668",
            "s:",
            "n:73.0",
            "n:2883.0",
            "n:6088.0"
        ]);
    sas7ExpectRow(
        $ds,
        9,
        [
            "n:0.663",
            "s:pear",
            "m:.",
            "n:7735.0",
            "n:0.086",
            "s:apple",
            "n:80.0",
            "m:.",
            "m:.",
            "s:pear",
            "n:16.0",
            "n:9159.0",
            "n:0.053",
            "s:dog",
            "n:52.0",
            "n:3478.0",
            "m:."
        ]);
    sas7ExpectMissing($ds, ["."], [72]);
}

func testSas7Rle64() {
    def ds as Dataset init sas7Read(SAS7_FILE_MAX_DATE);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M5");
    testing.assertEqual($ds.name, "MAX_SAS_DATE");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "iso-8859-15");
    testing.assertEqual($ds.rowCount, 2);
    testing.assertEqual(len($ds.variables), 5);
    sas7ExpectVariables(
        $ds,
        "names",
        ["text", "dt_as_float", "dt_as_dt", "date_as_float", "date_as_date"]);
    sas7ExpectVariables($ds, "labels", ["", "", "", "", ""]);
    sas7ExpectVariables($ds, "formats", ["$CHAR6.", "16.3", "DATETIME22.3", "7.", "E8601DA."]);
    sas7ExpectVariables($ds, "types", ["string", "numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["6", "8", "8", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        ["s:max", "n:253717747199.999", "n:253717747199.999", "n:2936547.0", "n:2936547.0"]);
    sas7ExpectRow(
        $ds,
        1,
        ["s:normal", "n:1880323199.999", "n:1880323199.999", "n:21762.0", "n:21762.0"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7ZeroRows() {
    def ds as Dataset init sas7Read(SAS7_FILE_ZERO_ROWS);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M5");
    testing.assertEqual($ds.name, "ZERO_ROWS_NO_COMPRESS");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "iso-8859-15");
    testing.assertEqual($ds.rowCount, 0);
    testing.assertEqual(len($ds.variables), 2);
    sas7ExpectVariables($ds, "names", ["char_field", "num_field"]);
    sas7ExpectVariables($ds, "labels", ["", ""]);
    sas7ExpectVariables($ds, "formats", ["", ""]);
    sas7ExpectVariables($ds, "types", ["string", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["3", "8"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7AmdPage() {
    def ds as Dataset init sas7Read(SAS7_FILE_AMD);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M7");
    testing.assertEqual($ds.name, "");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 33);
    testing.assertEqual(len($ds.variables), 16);
    sas7ExpectVariables(
        $ds,
        "names",
        [
            "OutStatus",
            "NetVariation",
            "QuestionNumber",
            "CellId",
            "NbAnonym",
            "AnonymTotalVar",
            "NbRespondents",
            "TotalVar",
            "Sensitivity",
            "Status",
            "Type",
            "TotalNoise",
            "Prov",
            "Naics",
            "cost1",
            "cost2"
        ]);
    sas7ExpectVariables(
        $ds,
        "labels",
        ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "formats",
        ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "types",
        [
            "string",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "string",
            "string",
            "numeric",
            "string",
            "string",
            "numeric",
            "numeric"
        ]);
    sas7ExpectVariables(
        $ds,
        "widths",
        ["1", "8", "8", "8", "8", "8", "8", "8", "8", "1", "1", "8", "1", "1", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        [
            "s:X",
            "n:15.149999999999991",
            "n:1.0",
            "n:1.0",
            "n:0.0",
            "n:0.0",
            "n:1.0",
            "n:101.0",
            "n:15.149999999999991",
            "s:S",
            "s:C",
            "n:101.0",
            "s:1",
            "s:1",
            "n:15.149999999999991",
            "n:15.149999999999991"
        ]);
    sas7ExpectRow(
        $ds,
        16,
        [
            "s:X",
            "n:15.149999999999991",
            "n:2.0",
            "n:17.0",
            "n:0.0",
            "n:0.0",
            "n:5.0",
            "n:912.0",
            "n:-360.54999999999995",
            "s:V",
            "s:C",
            "n:912.0",
            "s:1",
            "s:0",
            "n:360.54999999999995",
            "n:360.54999999999995"
        ]);
    sas7ExpectRow(
        $ds,
        32,
        [
            "s:X",
            "n:15.149999999999991",
            "n:3.0",
            "n:33.0",
            "n:0.0",
            "n:0.0",
            "n:2.0",
            "n:303.0",
            "n:30.299999999999983",
            "s:S",
            "s:A",
            "n:303.0",
            "s:",
            "s:",
            "n:30.299999999999983",
            "n:30.299999999999983"
        ]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7RdcFile() {
    def ds as Dataset init sas7Read(SAS7_FILE_BINCOMPRESSED);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M6");
    testing.assertEqual($ds.name, "BINCOMPRESSED");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(len($ds.variables), 7);
    sas7ExpectVariables(
        $ds,
        "names",
        ["mychar", "mynum", "mydate", "dtime", "mylabl", "myord", "mytime"]);
    sas7ExpectVariables($ds, "labels", ["", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "formats",
        ["$1.", "BEST12.", "YYMMDD10.", "DATETIME.", "BEST12.", "BEST12.", "TIME20.3"]);
    sas7ExpectVariables(
        $ds,
        "types",
        ["string", "numeric", "numeric", "numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["1", "8", "8", "8", "8", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        ["s:a", "n:1.1", "n:21310.0", "n:1841220610.0", "n:1.0", "n:1.0", "n:36610.0"]);
    sas7ExpectRow($ds, 2, ["s:c", "n:-1000.3", "n:0.0", "n:0.0", "n:1.0", "n:3.0", "n:0.0"]);
    sas7ExpectRow($ds, 4, ["s:e", "n:1000.3", "m:.", "m:.", "n:1.0", "n:1.0", "m:."]);
    sas7ExpectMissing($ds, ["."], [3]);
}

func testSas7SpecialMissing() {
    def ds as Dataset init sas7Read(SAS7_FILE_MISSING);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M3");
    testing.assertEqual($ds.name, "MISSING_TEST");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 1);
    testing.assertEqual(len($ds.variables), 9);
    sas7ExpectVariables(
        $ds,
        "names",
        ["var1", "var2", "var3", "var4", "var5", "var6", "var7", "var8", "var9"]);
    sas7ExpectVariables($ds, "labels", ["", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables($ds, "formats", ["A.", "", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "types",
        [
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric",
            "numeric"
        ]);
    sas7ExpectVariables($ds, "widths", ["8", "8", "8", "8", "8", "8", "8", "8", "8"]);
    sas7ExpectRow($ds, 0, ["m:.a", "m:.b", "m:.c", "m:.x", "m:.y", "m:.z", "m:._", "m:.", "n:1.0"]);
    sas7ExpectMissing(
        $ds,
        [".", "._", ".a", ".b", ".c", ".x", ".y", ".z"],
        [1, 1, 1, 1, 1, 1, 1, 1]);
}

func testSas7MovedRow() {
    def ds as Dataset init sas7Read(SAS7_FILE_MOVED_NONE);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M9");
    testing.assertEqual($ds.name, "");
    testing.assertEqual($ds.label, "SAS file with moved uncompressed row");
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(len($ds.variables), 3);
    sas7ExpectVariables($ds, "names", ["id", "category", "payload_to_update"]);
    sas7ExpectVariables($ds, "labels", ["", "", ""]);
    sas7ExpectVariables($ds, "formats", ["", "", ""]);
    sas7ExpectVariables($ds, "types", ["numeric", "string", "string"]);
    sas7ExpectVariables($ds, "widths", ["8", "20", "2000"]);
    sas7ExpectRow($ds, 0, ["n:1.0", "s:CATEGORY_1", "s:"]);
    sas7ExpectRow(
        $ds,
        2,
        [
            "n:3.0",
            "s:CATEGORY_3",
            "s:3743115d-3c25-be4c-b197-f78c5eeaa9d7 484328da-d7d4-e341-b1d5-1fe36313a014 9c3f5af8-b86b-3844-97b6-83359a92a8f0 cef9af38-eb57-7546-8fc2-955031385a2f 73c2f474-9c13-7c41-aacf-b38a2aa41171 a6e22be2-7145-064f-a0ee-f1fefdba625d e6b27c80-bfd6-8a44-be62-3deb623c0226 634992a4-a83c-b24a-88db-8f07118bdb66 8e1bac98-c712-2b4a-9e15-8ec21f901478 a844b342-7dcc-9b49-9874-e5649ab16a26 489c02ee-dda6-ff47-ae30-5e9fc06c9b02 befa427f-c0e7-7048-90ef-fa1d1b4199e7 b9f8771b-dead-7847-86c3-00aae3da7e86 e0f22a3c-ce09-ca40-8a7b-70da17481a57 17507a78-3bcf-ff47-baf0-117833084c98 010c8cf0-f8a5-2a42-81b1-19e99bbd0f87 a094d416-f1db-9b45-9bdf-78d7dd0e02ea 7d8b0142-931c-7d43-9243-f4b8ca0444be ad015756-e228-054a-a473-a17a27bb2214 22291e86-da61-254a-82b1-8d6bdb0efc35 99a605fc-902e-3f40-b1c0-08131484ab3d 52d348da-01be-cf45-b6ac-474636753d1d 0dc5ae6e-867b-694a-b72f-5aeb9a62e60e 310b5a50-656b-5642-b356-a55bed7442f2 80728ee3-fa1c-4a45-a302-11e3fef76601 1956f99e-bad7-7942-a156-24ff08a33f0a 1cfd5a84-4410-9047-b8f8-31eb6a9f7c28 499ba64a-d840-9148-a543-4f3ad65a07ba 39a1b204-66b3-8447-8768-e5ec9c8eb42d 0af724d1-e743-1d42-8f67-82e5a5d65c4a 58207c60-321e-bd44-8883-94434aff17f3 5b7c4b99-c913-124f-8206-b35d5642b0f9 5fded325-a0e7-b440-8e5e-ba63c492c4fe 57401e01-285f-a744-83bf-8a819bed768d 5e62f20f-2414-1d46-84d3-eed342945f61 1f427ad4-3403-8e48-8e4a-0edcdeb86619 b58ea426-e3d7-1c4f-8e9d-6be0ccdfdc6d 27eb1f4f-50c4-9144-8b64-40cefd154c25 81bc2203-f734-0c4a-98d4-842d44c97182 abd68222-b310-cf4a-b3fc-7276781be85e 5dbe713f-2561-264b-a00c-04ef00c79b25 bf039aea-f7bc-a64f-b169-6b5546735488 c7a7f584-5892-f640-9976-1417c5ff9deb 62022d6b-cc69-fb44-911a-d07846a15258 4e40c677-4beb-c14c-9952-01d0cf5f445f 138041b8-5f19-bd4c-b544-1cc173904a01 ab4573fd-9714-084c-965b-4a36b110a1a6 91a0f3e0-5c3e-8c4b-b216-217af2552d46 b48c80f7-781c-1442-8f7b-adfc40865f72 ac96bd64-ab60-e548-980a-6681c74fff13 aabc1509-cc09-614a-ba27-a157b3f4e031 5abf037b-3a83-1244-8031-df2a8d1c2cbb a92a6739-bc40-3c4e-9a47-0e98c2e07ebc 37ae1c59-4946-a24c-beb7-8de0e039ec76 f1"
        ]);
    sas7ExpectRow($ds, 4, ["n:5.0", "s:CATEGORY_5", "s:"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7MovedCompressedRow() {
    def ds as Dataset init sas7Read(SAS7_FILE_MOVED_ROW);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M9");
    testing.assertEqual($ds.name, "");
    testing.assertEqual($ds.label, "SAS file with moved compressed row");
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual($ds.rowCount, 5);
    testing.assertEqual(len($ds.variables), 3);
    sas7ExpectVariables($ds, "names", ["id", "category", "payload_to_update"]);
    sas7ExpectVariables($ds, "labels", ["", "", ""]);
    sas7ExpectVariables($ds, "formats", ["", "", ""]);
    sas7ExpectVariables($ds, "types", ["numeric", "string", "string"]);
    sas7ExpectVariables($ds, "widths", ["8", "20", "2000"]);
    sas7ExpectRow($ds, 0, ["n:1.0", "s:CATEGORY_1", "s:"]);
    sas7ExpectRow(
        $ds,
        2,
        [
            "n:3.0",
            "s:CATEGORY_3",
            "s:c12095a2-0924-bd43-a287-d7357c6bf608 bd65bfd5-6a5d-814d-8f2e-eacd2857432d bb7d15d3-0553-a541-b445-171a82065024 0e80798f-e2b8-1c4e-9e22-d487096333bb 116c5ca0-b567-4b4e-abe5-6a152797e040 c74a3cc7-f2c1-124a-a389-01e3608ad532 900b0dd7-cb89-c74e-a61d-f582f76370ac ae1322fd-1d89-f949-841d-4f64a3b714bb f0f592ba-06ea-ef4e-bb7c-fb81f96b9c35 ed46f9c1-5e16-024c-a6f7-c953fb55d9ed 06481d3e-8226-dc46-9cbf-acb4a3b137d7 397e6c19-5788-f246-915f-21c87bbcbeea be9c7c1c-abea-db4f-be92-8f4b9259581c 26bbcb82-997a-fe4f-886b-f6acbdc70e55 7e9e0af5-28c8-ef43-8f25-c9853e999813 93dfbf74-dd75-2747-9774-3054c7cd4d22 ff6ef538-8e60-814c-a4dc-43469ca61838 0de091fd-f3ad-5c44-a764-c04670e346b8 a2ecd84d-1b43-8740-b4e4-67e71df8e3c3 26c2042b-e40f-b148-a437-e6dbfdeb30f8 5bcf0782-0ffe-b44f-9f1c-f5001ea75ce1 93f67772-e672-1b46-a8b2-bef71efa7cd0 c20711ad-0b34-f147-af5e-4786639327bf 7e29c2b8-89b2-f347-9934-1db24be5b9d1 609bb1f4-87ee-2340-8139-52a35b0cfc65 aca27abd-ff29-2f49-b196-822644e3cbf7 f303e3de-4d1f-944b-a733-95484c577890 b73af91b-2faf-9843-a87d-d4a4034b46d0 bf4c42e6-4155-1c49-a2ae-50b793882f34 2b6bb55d-2215-644f-b5f7-fe286c28eb5d 39c1bad6-c83b-d048-b356-40ea6466cb36 1bcb6989-264b-134a-99fa-34477debea74 a2cf76c8-2260-b74c-ba6a-d6040f1cb177 7b5417ea-7549-d249-b9fa-a44b2a482a6f a855ab5e-a4f2-4f40-879f-b968c7fc9133 a77460df-cd65-bf4e-8fa1-26da4b587c3e 56c84e28-6686-0d45-a4e5-fa4aea37ff7f d84792e1-25ee-b249-b2ca-c8191335f06d 65f00537-59c0-b74c-a4d5-b48d08ad7642 917909b4-05a7-c449-b7d4-e668dc57bc96 b541e4e1-db09-c945-8b3d-1b67a5a67cb2 ec937d0b-d0ed-804e-abca-45941d8b4c9f ba08ac7f-6049-c849-a531-2e8618f4f9f6 72301aa7-2ee9-f748-8f85-13205bd3a401 4a5228c0-9de0-9746-9a68-d5078626740c b05408e9-2e4c-7d46-8682-b03d7e0fef8e 5e9c1631-d779-a24f-906f-416969190d4b 93320a2e-19c6-fd4c-98f9-4363a31390f3 d41c24ed-b085-be43-965d-b951780c4378 1b836551-242f-224f-bfca-3b5ad53cb53a 661ac21a-fe4b-fe44-95e6-f049e8526250 d3039b77-e165-dc4c-9d36-33dc07e8129f a6210624-79bc-2243-9e62-b23f96104c1e 8acdaaec-cbe2-9a4b-a15e-5dd9b09bbf10 f6"
        ]);
    sas7ExpectRow($ds, 4, ["n:5.0", "s:CATEGORY_5", "s:"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7DeletedCompressedRow() {
    def ds as Dataset init sas7Read(SAS7_FILE_COMP_DELETED);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0301M0");
    testing.assertEqual($ds.name, "TEST_4_COMP_3RDROW_REMOVED");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 3);
    testing.assertEqual(len($ds.variables), 4);
    sas7ExpectVariables($ds, "names", ["olumn1", "olumn2", "olumn3", "column4"]);
    sas7ExpectVariables($ds, "labels", ["", "", "", ""]);
    sas7ExpectVariables($ds, "formats", ["BEST8.", "BEST8.", "BEST8.", "BEST8."]);
    sas7ExpectVariables($ds, "types", ["numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["8", "8", "8", "8"]);
    sas7ExpectRow($ds, 0, ["n:1.0", "n:2.0", "n:3.0", "n:4.0"]);
    sas7ExpectRow($ds, 1, ["n:5.0", "n:6.0", "n:7.0", "n:8.0"]);
    sas7ExpectRow($ds, 2, ["n:55.0", "n:66.0", "n:77.0", "n:88.0"]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7DeletedPageRow() {
    def ds as Dataset init sas7Read(SAS7_FILE_PAGE_DELETED);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0301M0");
    testing.assertEqual($ds.name, "TESTSAMPLE");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 36);
    testing.assertEqual(len($ds.variables), 8);
    sas7ExpectVariables($ds, "names", ["x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8"]);
    sas7ExpectVariables($ds, "labels", ["", "", "", "", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "formats",
        ["BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12."]);
    sas7ExpectVariables(
        $ds,
        "types",
        ["numeric", "numeric", "numeric", "numeric", "numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["8", "8", "8", "8", "8", "8", "8", "8"]);
    sas7ExpectRow(
        $ds,
        0,
        [
            "n:0.0",
            "n:1.7728319648062687",
            "n:1.5596184510415154",
            "n:-0.07548413371237805",
            "n:-0.12731038690566573",
            "n:1.271609711166061",
            "n:-0.3734850889273111",
            "n:-0.49147829993398395"
        ]);
    sas7ExpectRow(
        $ds,
        18,
        [
            "n:100.0",
            "n:-0.8857231458857177",
            "n:0.9116844893369325",
            "n:0.07257983569198122",
            "n:0.29851240591722894",
            "n:1.1581223892981787",
            "n:-0.09541930254091151",
            "n:0.1057427226663258"
        ]);
    sas7ExpectRow(
        $ds,
        35,
        [
            "n:9000.0",
            "n:-0.30020303167021406",
            "n:2.707794781904498",
            "n:0.037898762220474204",
            "n:1.8252323273998958",
            "n:-1.0410391489065178",
            "n:-0.10034451701714392",
            "n:0.04083665080022068"
        ]);
    sas7ExpectMissing($ds, [], []);
}

func testSas7Tagged() {
    def ds as Dataset init sas7Read(SAS7_FILE_TAGGED);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M2");
    testing.assertEqual($ds.name, "APPLE");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 8);
    testing.assertEqual(len($ds.variables), 1);
    sas7ExpectVariables($ds, "names", ["x"]);
    sas7ExpectVariables($ds, "labels", [""]);
    sas7ExpectVariables($ds, "formats", ["XFMT."]);
    sas7ExpectVariables($ds, "types", ["numeric"]);
    sas7ExpectVariables($ds, "widths", ["8"]);
    sas7ExpectRow($ds, 0, ["n:1.0"]);
    sas7ExpectRow($ds, 4, ["n:5.0"]);
    sas7ExpectRow($ds, 5, ["m:.a"]);
    sas7ExpectRow($ds, 6, ["m:.h"]);
    sas7ExpectRow($ds, 7, ["m:.z"]);
    sas7ExpectMissing($ds, [".a", ".h", ".z"], [1, 1, 1]);
}

func testSas7Hadley() {
    def ds as Dataset init sas7Read(SAS7_FILE_HADLEY);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M1");
    testing.assertEqual($ds.name, "HADLEY");
    testing.assertEqual($ds.label, "");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 8);
    testing.assertEqual(len($ds.variables), 7);
    sas7ExpectVariables($ds, "names", ["id", "workshop", "gender", "q1", "q2", "q3", "q4"]);
    sas7ExpectVariables(
        $ds,
        "labels",
        [
            "",
            "",
            "",
            "The instructor was well prepared",
            "The instructor communicated well",
            "The course material was helpful",
            "Overall, I found the workhsop useful"
        ]);
    sas7ExpectVariables($ds, "formats", ["", "WORKSHOP.", "$GENDER.", "", "", "", ""]);
    sas7ExpectVariables(
        $ds,
        "types",
        ["numeric", "numeric", "string", "numeric", "numeric", "numeric", "numeric"]);
    sas7ExpectVariables($ds, "widths", ["8", "8", "8", "8", "8", "8", "8"]);
    sas7ExpectRow($ds, 0, ["n:1.0", "n:1.0", "s:f", "n:1.0", "n:1.0", "n:5.0", "n:1.0"]);
    sas7ExpectRow($ds, 3, ["n:4.0", "n:2.0", "s:", "n:3.0", "n:1.0", "m:.", "n:3.0"]);
    sas7ExpectRow($ds, 4, ["n:5.0", "n:1.0", "s:m", "n:4.0", "n:5.0", "n:2.0", "n:4.0"]);
    sas7ExpectRow($ds, 7, ["n:8.0", "n:2.0", "s:m", "n:4.0", "n:5.0", "n:5.0", "n:5.0"]);
    sas7ExpectMissing($ds, ["."], [1]);
}

func testSas7WidthsBigEndian() {
    def ds as Dataset init sas7Read(SAS7_FILE_WIDTHS_BE);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M5");
    testing.assertEqual($ds.name, "WIDTHS");
    testing.assertEqual($ds.label, "Generated for timing");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 12);
    testing.assertEqual(len($ds.variables), 7);
    sas7ExpectVariables($ds, "names", ["w3", "w4", "w5", "w6", "w7", "w8", "s0"]);
    sas7ExpectVariables(
        $ds,
        "labels",
        ["Width 3", "Width 4", "Width 5", "Width 6", "Width 7", "Width 8", "Text"]);
    sas7ExpectVariables(
        $ds,
        "formats",
        ["BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "$CHAR12."]);
    sas7ExpectVariables(
        $ds,
        "types",
        ["numeric", "numeric", "numeric", "numeric", "numeric", "numeric", "string"]);
    sas7ExpectVariables($ds, "widths", ["3", "4", "5", "6", "7", "8", "12"]);
    sas7ExpectRow(
        $ds,
        0,
        ["n:-346.0", "n:-451.0", "n:10119.5", "n:13193.5", "n:8255.25", "n:126.78", "s:delta"]);
    sas7ExpectRow($ds, 1, ["m:.", "m:.", "m:.", "m:.", "m:.", "m:.", "s:alpha"]);
    sas7ExpectRow($ds, 4, ["m:.z", "m:.z", "m:.z", "m:.z", "m:.z", "m:.z", "s:omega long"]);
    sas7ExpectRow(
        $ds,
        6,
        ["n:184.0", "n:71.0", "n:-4438.25", "n:-2050.75", "n:13004.0", "n:112.08", "s:Zürich"]);
    sas7ExpectRow($ds, 7, ["m:._", "m:._", "m:._", "m:._", "m:._", "m:._", "s:omega long"]);
    sas7ExpectRow(
        $ds,
        11,
        ["n:351.0", "n:-231.0", "n:-15453.0", "n:-800.75", "n:-4119.5", "n:81.72", "s:alpha"]);
    sas7ExpectMissing($ds, [".", "._", ".z"], [12, 6, 6]);
}

func testSas7WidthsLittleEndianRle() {
    def ds as Dataset init sas7Read(SAS7_FILE_WIDTHS_LE);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.version, "9.0401M5");
    testing.assertEqual($ds.name, "WIDTHS");
    testing.assertEqual($ds.label, "Generated for timing");
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual($ds.rowCount, 12);
    testing.assertEqual(len($ds.variables), 7);
    sas7ExpectVariables($ds, "names", ["w3", "w4", "w5", "w6", "w7", "w8", "s0"]);
    sas7ExpectVariables(
        $ds,
        "labels",
        ["Width 3", "Width 4", "Width 5", "Width 6", "Width 7", "Width 8", "Text"]);
    sas7ExpectVariables(
        $ds,
        "formats",
        ["BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "BEST12.", "$CHAR12."]);
    sas7ExpectVariables(
        $ds,
        "types",
        ["numeric", "numeric", "numeric", "numeric", "numeric", "numeric", "string"]);
    sas7ExpectVariables($ds, "widths", ["3", "4", "5", "6", "7", "8", "12"]);
    sas7ExpectRow(
        $ds,
        0,
        ["n:-346.0", "n:-451.0", "n:10119.5", "n:13193.5", "n:8255.25", "n:126.78", "s:delta"]);
    sas7ExpectRow($ds, 1, ["m:.", "m:.", "m:.", "m:.", "m:.", "m:.", "s:alpha"]);
    sas7ExpectRow($ds, 4, ["m:.z", "m:.z", "m:.z", "m:.z", "m:.z", "m:.z", "s:omega long"]);
    sas7ExpectRow(
        $ds,
        6,
        ["n:184.0", "n:71.0", "n:-4438.25", "n:-2050.75", "n:13004.0", "n:112.08", "s:Zürich"]);
    sas7ExpectRow($ds, 7, ["m:._", "m:._", "m:._", "m:._", "m:._", "m:._", "s:omega long"]);
    sas7ExpectRow(
        $ds,
        11,
        ["n:351.0", "n:-231.0", "n:-15453.0", "n:-800.75", "n:-4119.5", "n:81.72", "s:alpha"]);
    sas7ExpectMissing($ds, [".", "._", ".z"], [12, 6, 6]);
}

func testSas7ShortRows() {
    # rows that did not shrink are stored uncompressed, as subheaders too
    # short for a signature and its length field (5 bytes in a 32-bit file,
    # 9 in a 64-bit one); pyreadstat reads both
    def ds as Dataset init sas7Read(SAS7_FILE_SHORT32);
    testing.assertEqual($ds.name, "SHORT");
    testing.assertEqual($ds.encoding, "utf-8");
    sas7ExpectVariables($ds, "names", ["s"]);
    sas7ExpectVariables($ds, "widths", ["5"]);
    testing.assertEqual(textColumn($ds, "s"), ["abcde", "", "x", "é", ""]);
    $ds = sas7Read(SAS7_FILE_SHORT64);
    sas7ExpectVariables($ds, "widths", ["9"]);
    testing.assertEqual(textColumn($ds, "s"), ["abcdefghi", "", "xy", "Zürich", ""]);
}

func testSas7ShortColumns() {
    # numbers of 3 to 7 bytes are read in bulk; every cell must equal the
    # cell by cell conversion bit for bit (compared through %v, which tells
    # -0.0 from 0.0), with the windows of the first column (little-endian)
    # and of the last one (big-endian) running past the buffer
    def offsets as list of int init [0, 3, 7, 9, 14, 20, 27, 35, 38];
    def widths as list of int init [3, 4, 2, 5, 6, 7, 8, 3, 7];
    def numeric as list of bool init [true, true, false, true, true, true, true, true, true];
    for (def order in ["le", "be"]) {
        sas7ExpectShort($order, $offsets, $widths, $numeric, 45, 300);
        sas7ExpectShort($order, $offsets, $widths, $numeric, 45, 1);
        # little-endian windows one byte apart: they must not share a mask
        sas7ExpectShort(
            $order,
            [0, 8, 11, 13, 18],
            [8, 3, 2, 5, 12],
            [true, true, false, true, false],
            30,
            50);
        # a row shorter than a double: one column at a time
        sas7ExpectShort($order, [0], [5], [true], 5, 40);
        sas7ExpectShort($order, [0, 3], [3, 3], [true, true], 6, 40);
    }
}

/**
 * Build rows of the given columns, decode them through sas7Decode and
 * compare every numeric cell with sas7Numbers over sas7RawColumn.
 *
 * @param order {string} `le` or `be`
 * @param offsets {list of int} the columns' offsets
 * @param widths {list of int} their widths
 * @param numeric {list of bool} which are numbers
 * @param rl {int} the row length
 * @param rows {int} the number of rows
 */
func sas7ExpectShort(
    order as string,
    offsets as list of int,
    widths as list of int,
    numeric as list of bool,
    rl as int,
    rows as int) {
    # zeros, signs, extremes, subnormals, missing values ., .A, .Z, ._ (as
    # index 0 and as code), a NaN SAS does not write, then pseudo-random
    # patterns
    def special as list of int init [
        0,
        sas7Pattern(0x80000000, 0),
        sas7Pattern(0x40590000, 0),
        sas7Pattern(0xC0FE2400, 0x12345678),
        sas7Pattern(0xFFFFD100, 0),
        sas7Pattern(0xFFFFBE00, 0),
        sas7Pattern(0xFFFFA500, 0),
        sas7Pattern(0xFFFFFF00, 0),
        sas7Pattern(0xFFFFA000, 0),
        sas7Pattern(0x7FEFFFFF, 0xFFFFFFFF),
        sas7Pattern(0x00000123, 0),
        sas7Pattern(0x800FFFFF, 0xFFFFFFFF),
        sas7Pattern(0x7FF80000, 0)
    ];
    def flat as bytes init binary.make($rl * $rows, 0x20);
    def seed as int init 12345;
    for (def r in 0..$rows) {
        for (def i in 0..len($offsets)) {
            if (not $numeric[$i]) {
                continue;
            }
            def raw as int;
            if (($r == 0 or $r == $rows - 1) and $i % 2 == 0) {
                # missing values in the rows read on their own
                $raw = $special[4 + ($i // 2) % 5];
            } elseif (($r + $i) % 3 == 0) {
                $raw = $special[($r + 2 * $i) % len($special)];
            } else {
                $seed = ($seed * 1103515245 + 12345) % 2147483648;
                def hi as int init $seed;
                $seed = ($seed * 1103515245 + 12345) % 2147483648;
                $raw = sas7Pattern($hi * 2 + $seed % 2, $seed * 2);
                if ((($raw >> 52) & 0x7FF) == 0x7FF) {
                    $raw = $raw ^ sas7Pattern(0x40000000, 0);
                }
            }
            for (def k in 0..$widths[$i]) {
                def at as int init $r * $rl + $offsets[$i] + $k;
                if ($order == "le") {
                    $at = $r * $rl + $offsets[$i] + $widths[$i] - 1 - $k;
                }
                $flat[$at] = ($raw >> (56 - 8 * $k)) & 0xFF;
            }
        }
    }
    def m as Sas7Meta init Sas7Meta{
        texts: [],
        rowSizeSeen: true,
        rowLength: $rl,
        totalRows: $rows,
        deletedRows: 0,
        mixRows: 0,
        labelRef: [0, 0, 0],
        compressionRef: [0, 0, 0],
        columnCount: len($offsets),
        nameRefs: [],
        offsets: $offsets,
        widths: $widths,
        numeric: $numeric,
        formatWidths: [],
        formatDigits: [],
        formatRefs: [],
        labelRefs: []
    };
    def head as Sas7Head init Sas7Head{
        u64: true,
        order: $order,
        align: 4,
        headerSize: 8192,
        pageSize: 65536,
        pageCount: 1,
        pageHead: 40,
        pointerSize: 24,
        word: 8,
        release: "9.0401M5",
        statTransfer: false,
        name: binary.make(0),
        charset: "utf-8"
    };
    def variables as list of Variable init [];
    for (def i in 0..len($offsets)) {
        $variables[] = Variable{
            name: io.sprintf("v%d", $i),
            label: "",
            type: "numeric",
            storage: "numeric",
            width: $widths[$i],
            format: "",
            valueLabels: {},
            missingValues: [],
            missingRange: []
        };
    }
    def ds as Dataset init sas7Decode($flat, $head, $m, $variables, $rows);
    for (def i in 0..len($offsets)) {
        if (not $numeric[$i]) {
            continue;
        }
        def col as Sas7Column init sas7Numbers(
            sas7RawColumn($flat, $offsets[$i], $rows, $widths[$i], $rl, $order),
            "x");
        testing.assertEqual($ds.missing[$i], $col.missing);
        def got as list of string init [];
        def want as list of string init [];
        for (def r in 0..$rows) {
            $got[] = io.sprintf("%v", $ds.numbers[$i][$r]);
            $want[] = io.sprintf("%v", $col.numbers[$r]);
        }
        testing.assertEqual($got, $want);
    }
}

/**
 * Bytes from a list of byte values.
 *
 * @param values {list of int} the bytes
 * @return {bytes} the buffer
 */
func sas7Bytes(values as list of int) {
    return sas7Patch(binary.make(len($values)), 0, $values);
}

/**
 * A 64-bit pattern from its two 32-bit halves.
 *
 * @param hi {int} the high half
 * @param lo {int} the low half
 * @return {int} the pattern
 */
func sas7Pattern(hi as int, lo as int) {
    return ($hi << 32) | $lo;
}

/**
 * The kind of the error unpacking a compressed row throws, `""` when it
 * unpacks.
 *
 * @param stream {list of int} the compressed bytes
 * @param rl {int} the row length
 * @param compression {string} `rle` or `rdc`
 * @return {string} the kind
 */
func sas7UnpackKind(stream as list of int, rl as int, compression as string) {
    try {
        sas7Unpack(sas7Bytes($stream), 0, len($stream), $rl, $compression);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * Unpack a compressed row from a list of bytes.
 *
 * @param stream {list of int} the compressed bytes
 * @param rl {int} the row length
 * @param compression {string} `rle` or `rdc`
 * @return {string} the row as ISO-8859-1 text
 */
func sas7UnpackText(stream as list of int, rl as int, compression as string) {
    return encoding.decode(
        "iso-8859-1",
        sas7Unpack(sas7Bytes($stream), 0, len($stream), $rl, $compression));
}

func testSas7Detect() {
    def data as bytes init sas7Fixture(SAS7_FILE_TAGGED);
    def catalog as bytes init sas7Fixture(SAS7_CATALOG_TAGGED);
    testing.assertEqual(detect($data), "sas7bdat");
    testing.assertEqual(detect($catalog), "sas7bcat");
    testing.assertFalse(looksLikeSas7bdat(binary.slice($data, 0, 31)));
    testing.assertFalse(looksLikeSas7bdat(binary.make(64)));
    testing.assertFalse(looksLikeSas7bcat($data));
    def ds as Dataset init read($data);
    testing.assertEqual($ds.format, "sas7bdat");
    testing.assertEqual($ds.rowCount, 8);
    try {
        read($catalog);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    testing.assertEqual(sas7ErrorKind($catalog, options()), ERROR_KIND);
    testing.assertEqual(sas7ErrorKind(binary.make(2048), options()), ERROR_KIND);
}

func testSas7Encoding() {
    def data as bytes init sas7Fixture(SAS7_FILE_WIDTHS_LE);
    def ds as Dataset init readSas7bdat($data, options());
    testing.assertEqual($ds.encoding, "utf-8");
    testing.assertEqual(textColumn($ds, "s0")[6], "Zürich");
    def opts as Options init options();
    $opts.encoding = "latin1";
    $ds = readSas7bdat($data, $opts);
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual(textColumn($ds, "s0")[6], "ZÃ¼rich");
    $opts.encoding = "klingon";
    testing.assertEqual(sas7ErrorKind($data, $opts), ERROR_KIND);
    # GB18030, which the encoding library lacks: an error that names it,
    # unless Options.encoding says how to read the text
    $data = sas7Fixture(SAS7_FILE_CHINESE);
    testing.assertTrue(strings.contains(sas7ErrorMessage($data, options()), "gb18030"));
    $opts.encoding = "iso-8859-1";
    $ds = readSas7bdat($data, $opts);
    testing.assertEqual($ds.rowCount, 1);
    testing.assertEqual($ds.numbers[0][0], 123.0);
    testing.assertEqual(sas7Charset(0), "windows-1252");
    testing.assertEqual(sas7Charset(204), "windows-1252");
    testing.assertEqual(sas7Charset(20), "utf-8");
    testing.assertEqual(sas7Charset(30), "iso-8859-2");
    testing.assertEqual(sas7Charset(61), "windows-1251");
    testing.assertEqual(sas7Charset(242), "iso-8859-13");
}

func testSas7Numbers() {
    def raws as list of int init [
        sas7Pattern(0x3FF00000, 0),
        sas7Pattern(0xBFF00000, 0),
        sas7Pattern(0x7FEFFFFF, 0xFFFFFFFF),
        1,
        sas7Pattern(0x80000000, 0),
        sas7Pattern(0x3FB99999, 0x9999999A),
        sas7Pattern(0xFFFFFE00, 0),
        sas7Pattern(0xFFFFFD00, 0),
        sas7Pattern(0xFFFFE400, 0),
        sas7Pattern(0xFFFFFF00, 0),
        sas7Pattern(0x7FF80000, 0),
        sas7Pattern(0xFFFFBD00, 0)
    ];
    def col as Sas7Column init sas7Numbers($raws, "x");
    testing.assertEqual($col.numbers[0], 1.0);
    testing.assertEqual($col.numbers[1], -1.0);
    testing.assertEqual($col.numbers[2], 1.7976931348623157e308);
    testing.assertEqual($col.numbers[3], math.pow(2.0, -1074));
    testing.assertTrue($col.numbers[3] > 0.0 and $col.numbers[3] / 2.0 == 0.0);
    testing.assertEqual($col.numbers[4], 0.0);
    testing.assertEqual($col.numbers[5], 0.1);
    testing.assertEqual($col.missing, ["", "", "", "", "", "", ".", ".a", ".z", "._", ".", ".b"]);
    try {
        sas7Numbers([sas7Pattern(0x7FF00000, 0)], "x");
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    # a 3-byte number keeps its top bytes, in either byte order
    def b as bytes init sas7Bytes([0x00, 0xF0, 0x3F, 0x40, 0x09, 0x00]);
    testing.assertEqual(sas7RawColumn($b, 0, 1, 3, 3, "le"), [sas7Pattern(0x3FF00000, 0)]);
    testing.assertEqual(sas7RawColumn($b, 3, 1, 3, 3, "be"), [sas7Pattern(0x40090000, 0)]);
}

func testSas7Rle() {
    def abc as list of int init [0x61, 0x62, 0x63];
    testing.assertEqual(sas7UnpackText(lists.concat([0x82], $abc), 3, "rle"), "abc");
    testing.assertEqual(sas7UnpackText([0xE1, 0xC0, 0x41, 0xF0], 8, "rle"), "   AAA\u0000\u0000");
    testing.assertEqual(sas7UnpackText([0x50, 0x00], 17, "rle"), strings.repeat("@", 17));
    testing.assertEqual(sas7UnpackText([0x40, 0x02, 0x7A], 20, "rle"), strings.repeat("z", 20));
    testing.assertEqual(
        sas7UnpackText([0x60, 0x01, 0xD0], 20, "rle"),
        strings.repeat(" ", 18) + "@@");
    def long as list of int init [0x00, 0x00];
    def copy96 as list of int init [0x20];
    for (def i in 0..96) {
        if ($i < 64) {
            $long[] = 0x78;
        }
        $copy96[] = 0x79;
    }
    testing.assertEqual(sas7UnpackText($long, 64, "rle"), strings.repeat("x", 64));
    testing.assertEqual(sas7UnpackText($copy96, 96, "rle"), strings.repeat("y", 96));
    testing.assertEqual(sas7UnpackKind([0x30], 3, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x82, 0x61], 3, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0xC0], 3, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x40, 0x00], 18, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind(lists.concat([0x82], $abc), 2, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind(lists.concat([0x82], $abc), 4, "rle"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x82, 0x61, 0x62, 0x63], 3, ""), ERROR_KIND);
}

func testSas7Rdc() {
    testing.assertEqual(sas7UnpackText([0x00, 0x00, 0x61, 0x62, 0x63], 3, "rdc"), "abc");
    testing.assertEqual(sas7UnpackText([0x80, 0x00, 0x00, 0x41], 3, "rdc"), "AAA");
    testing.assertEqual(
        sas7UnpackText([0x80, 0x00, 0x10, 0x01, 0x42], 35, "rdc"),
        strings.repeat("B", 35));
    # literals, then a copy of 3 bytes from 3 back
    testing.assertEqual(
        sas7UnpackText([0x10, 0x00, 0x61, 0x62, 0x63, 0x30, 0x00], 6, "rdc"),
        "abcabc");
    # an overlapping copy of 6, and a long copy of 20, from 3 back
    testing.assertEqual(
        sas7UnpackText([0x10, 0x00, 0x61, 0x62, 0x63, 0x60, 0x00], 9, "rdc"),
        "abcabcabc");
    testing.assertEqual(
        sas7UnpackText([0x10, 0x00, 0x61, 0x62, 0x63, 0x20, 0x00, 0x04], 23, "rdc"),
        strings.repeat("abc", 7) + "ab");
    # a copy from before the start, a command cut short, a stray byte, too
    # long and too short
    testing.assertEqual(sas7UnpackKind([0x80, 0x00, 0x30, 0x00], 3, "rdc"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x80, 0x00, 0x00], 3, "rdc"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x80, 0x00, 0x10, 0x01], 35, "rdc"), ERROR_KIND);
    testing.assertEqual(
        sas7UnpackKind([0x00, 0x00, 0x61, 0x62, 0x63, 0x00, 0x00, 0x64], 3, "rdc"),
        ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x00, 0x00, 0x61, 0x62, 0x63], 2, "rdc"), ERROR_KIND);
    testing.assertEqual(sas7UnpackKind([0x00, 0x00, 0x61, 0x62, 0x63], 4, "rdc"), ERROR_KIND);
}

func testSas7Truncated() {
    # the header states the size of the file, so every cut is an error
    def data as bytes init sas7Fixture(SAS7_FILE_WIDTHS_BE);
    for (def cut in 0..len($data)) {
        if ($cut % 97 == 0 or $cut < 300 or $cut % 4096 == 0 or $cut % 4096 == 4095) {
            testing.assertEqual(sas7ErrorKind(binary.slice($data, 0, $cut), options()), ERROR_KIND);
        }
    }
    # a file cut at a page boundary with the page count lowered loses rows
    def short as bytes init sas7Patch(binary.slice($data, 0, 12288), 208, [0, 0, 0, 0, 0, 0, 0, 1]);
    testing.assertTrue(strings.contains(
        sas7ErrorMessage($short, options()),
        "declares 12 rows but holds 0"));
    testing.assertEqual(sas7ErrorKind(binary.concat($data, binary.make(1)), options()), ERROR_KIND);
}

func testSas7Corrupt() {
    # widths_be: 64-bit big-endian, a meta page at 8192 and a data page at 12288
    def data as bytes init sas7Fixture(SAS7_FILE_WIDTHS_BE);
    def opts as Options init options();
    testing.assertEqual(sas7ErrorKind($data, $opts), "");
    def bad as list of bytes init [
        sas7Patch($data, 0, [1]),
        sas7Patch($data, 37, [2]),
        sas7Patch($data, 200, [0, 0, 2, 0]),
        sas7Patch($data, 204, [0, 0, 32, 0]),
        sas7Patch($data, 224, [0x58]),
        sas7Patch($data, 70, [99]),
        sas7Patch($data, 70, [69])
    ];
    def rs as int init sas7Locate($data, SAS7_SH_ROW_SIZE);
    def attrs as int init sas7Locate($data, SAS7_SH_ATTRS);
    def names as int init sas7Locate($data, SAS7_SH_NAME);
    def format as int init sas7Locate($data, SAS7_SH_FORMAT);
    def sizes as int init sas7Locate($data, SAS7_SH_COLUMN_SIZE);
    # row size: a longer row than a page, more deleted rows than rows, more
    # or fewer rows than the file holds, a mix page that cannot hold its rows
    $bad[] = sas7Patch($data, $rs + 44, [0, 1, 0, 0]);
    $bad[] = sas7Patch($data, $rs + 63, [13]);
    $bad[] = sas7Patch($data, $rs + 54, [3, 232]);
    $bad[] = sas7Patch($data, $rs + 55, [5]);
    $bad[] = sas7Patch($data, $rs + 120, [0x7F, 0xFF, 0xFF, 0xFF]);
    # columns: the count, a type, a numeric width, an offset, a name
    # reference, a format with decimals but no width
    $bad[] = sas7Patch($data, $sizes + 15, [8]);
    $bad[] = sas7Patch($data, $attrs + 30, [3]);
    $bad[] = sas7Patch($data, $attrs + 27, [9]);
    $bad[] = sas7Patch($data, $attrs + 16, [0x7F, 0xFF, 0xFF, 0xFF]);
    $bad[] = sas7Patch($data, $names + 20, [0xFF, 0xFF]);
    $bad[] = sas7Patch($data, $format + 24, [0, 0, 0, 2]);
    # a subheader pointer outside its page, an infinite number in row 0
    $bad[] = sas7Patch($data, 8192 + 40, [0x7F]);
    $bad[] = sas7Patch($data, 12288 + 40 + 25, [0x7F, 0xF0, 0, 0, 0, 0, 0, 0]);
    for (def b in $bad) {
        testing.assertEqual(sas7ErrorKind($b, $opts), ERROR_KIND);
    }
    testing.assertEqual(sas7ErrorKind(sas7Patch($data, $rs + 51, [1]), $opts), "limit");
    # a compressed row of an unknown compression code
    $data = sas7Fixture(SAS7_FILE_WIDTHS_LE);
    def pages as Sas7Pages init sas7Pages($data, sas7Head($data, $opts));
    def row as int init lists.indexOf($pages.ptrComps, SAS7_COMP_ROW);
    def at as int init 8192 + 40 + 24 * $row + 16;
    testing.assertEqual(sas7ErrorKind(sas7Patch($data, $at, [7]), $opts), ERROR_KIND);
    testing.assertEqual(
        sas7ErrorKind(sas7Patch($data, $at, [SAS7_COMP_DELETED]), $opts),
        ERROR_KIND);
}

func testSas7CorruptSweep() {
    # bytes of the page of an RLE file, inverted (every byte of the page
    # header and the subheader pointers, every ninth after them): an error of
    # kind statfiles or limit, or a file that still reads. The full sweeps
    # over many samples were run outside the deck.
    def data as bytes init sas7Fixture(SAS7_FILE_WIDTHS_LE);
    def opts as Options init options();
    def pages as Sas7Pages init sas7Pages($data, sas7Head($data, $opts));
    def pointers as int init 8192 + 40 + 24 * $pages.pointerCount[0];
    for (def at in 8192..len($data)) {
        if ($at >= $pointers and $at % 9 != 0) {
            continue;
        }
        def kind as string init sas7ErrorKind(sas7Patch($data, $at, [$data[$at] ^ 0xFF]), $opts);
        testing.assertTrue($kind == "" or $kind == ERROR_KIND or $kind == "limit");
    }
}

func testSas7Limits() {
    def data as bytes init sas7Fixture(SAS7_FILE_WIDTHS_LE);
    def opts as Options init options();
    $opts.maxCells = 83;
    testing.assertEqual(sas7ErrorKind($data, $opts), "limit");
    $opts.maxCells = 84;
    testing.assertEqual(sas7ErrorKind($data, $opts), "");
    # 12 compressed rows of 45 bytes unpack to 540 bytes
    $opts.maxBytes = 539;
    testing.assertEqual(sas7ErrorKind($data, $opts), "limit");
    $opts.maxBytes = 540;
    testing.assertEqual(sas7ErrorKind($data, $opts), "");
    # maxBytes does not apply to an uncompressed file
    $opts.maxBytes = 1;
    testing.assertEqual(sas7ErrorKind(sas7Fixture(SAS7_FILE_WIDTHS_BE), $opts), "");
    $opts.maxCells = 0;
    testing.assertEqual(sas7ErrorKind($data, $opts), ERROR_KIND);
}
