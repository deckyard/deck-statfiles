# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# statfiles - white-box tests for the xpt topic. Spliced into
# statfiles_test.j via include. Every expected value was cross-checked
# against pyreadstat 1.3.8 (ReadStat) and, for version 5, pandas.read_sas.

include "fixtures/xptfiles_test.j";

/**
 * A sample file from its base64 lines.
 *
 * @param lines {list of string} one of the XPT_* constants
 * @return {bytes} the file
 */
func xptFixture(lines as list of string) {
    return encoding.fromText("base64", strings.join($lines, ""));
}

/**
 * Read a one-member file with the default options.
 *
 * @param data {bytes} the file
 * @return {Dataset} the member
 */
func xptRead(data as bytes) {
    return readXpt($data, options());
}

/**
 * The kind of the error reading a file throws, `""` when it reads.
 *
 * @param data {bytes} the file
 * @return {string} the kind
 */
func xptKind(data as bytes) {
    try {
        readXptMembers($data, options());
    } catch (e) {
        return $e.kind;
    }
    return "";
}

/**
 * A copy of a file with ASCII text written over it.
 *
 * @param data {bytes} the file
 * @param at {int} the first byte to replace
 * @param text {string} the text
 * @return {bytes} the patched copy
 */
func xptPatch(data as bytes, at as int, text as string) {
    def b as bytes init encoding.encode("ascii", $text);
    for (def i in 0..len($b)) {
        $data[$at + $i] = $b[$i];
    }
    return $data;
}

/**
 * The offset of the first occurrence of ASCII text.
 *
 * @param data {bytes} the file
 * @param text {string} the text
 * @return {int} its offset, -1 if absent
 */
func xptFind(data as bytes, text as string) {
    return binary.indexOf($data, encoding.encode("ascii", $text));
}

func testXptDetect() {
    testing.assertEqual(detect(xptFixture(XPT_V5_BASIC)), "xpt");
    testing.assertEqual(detect(xptFixture(XPT_V8_LONG)), "xpt");
    testing.assertFalse(looksLikeXpt(binary.make(79, 32)));
    testing.assertFalse(looksLikeXpt(binary.make(160, 32)));
    def ds as Dataset init read(xptFixture(XPT_V8_LONG));
    testing.assertEqual($ds.format, "xpt");
}

func testXptV5Values() {
    def ds as Dataset init xptRead(xptFixture(XPT_V5_BASIC));
    testing.assertEqual($ds.format, "xpt");
    testing.assertEqual($ds.version, "5");
    testing.assertEqual($ds.name, "CLASS");
    testing.assertEqual($ds.label, "Class list");
    testing.assertEqual($ds.encoding, "windows-1252");
    testing.assertEqual($ds.rowCount, 7);
    testing.assertEqual(names($ds), ["id", "height", "born", "name", "big"]);
    testing.assertEqual(column($ds, "id"), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
    testing.assertEqual($ds.numbers[1], [0.1, -2.25, 123456789.125, 1e-5, 0.0, -1e10, 0.0]);
    testing.assertEqual($ds.missing[1], ["", "", "", "", "", "", "."]);
    testing.assertEqual(missingCode($ds, "born", 4), ".");
    testing.assertEqual(number($ds, "born", 0), 21915.0);
    testing.assertEqual(number($ds, "born", 1), -1.0);
    testing.assertEqual(
        textColumn($ds, "name"),
        ["Ada", "Grace", "", "Edsger W.", "x", "Barbara", "Niklaus"]);
    testing.assertEqual($ds.numbers[3], []);
    testing.assertEqual($ds.texts[0], []);
    testing.assertEqual($ds.missing[3], ["", "", "", "", "", "", ""]);
}

func testXptV5Variables() {
    def ds as Dataset init xptRead(xptFixture(XPT_V5_BASIC));
    def id as Variable init variable($ds, "id");
    testing.assertEqual($id.label, "Identifier");
    testing.assertEqual($id.type, "numeric");
    testing.assertEqual($id.storage, "numeric");
    testing.assertEqual($id.width, 8);
    testing.assertEqual($id.format, "8.");
    testing.assertEqual(variable($ds, "height").format, "8.2");
    testing.assertEqual(variable($ds, "born").format, "DATE9.");
    def name as Variable init variable($ds, "name");
    testing.assertEqual($name.type, "string");
    testing.assertEqual($name.storage, "string");
    testing.assertEqual($name.width, 9);
    testing.assertEqual($name.format, "$CHAR9.");
    testing.assertEqual($name.label, "Given name");
    testing.assertEqual($name.valueLabels, {});
    testing.assertEqual($name.missingValues, []);
    testing.assertEqual(variable($ds, "big").label, "");
    testing.assertEqual(variable($ds, "big").format, "");
}

func testXptIbmRange() {
    # pyreadstat writes 1e300, over the IBM range, as the largest IBM
    # value; numbers down to 16^-65 survive
    def ds as Dataset init xptRead(xptFixture(XPT_V5_BASIC));
    def big as list of float init $ds.numbers[4];
    testing.assertEqual($big[0], 7.2370055773322614e75);
    testing.assertEqual($big[1], -1e-70);
    testing.assertEqual($big[2], 7.2370055773322614e75);
    testing.assertEqual($big[3], 7e-78);
    testing.assertEqual($big[6], 1e15);
}

func testXptPowers() {
    def p as list of float init xptPowers();
    testing.assertEqual(len($p), 520);
    testing.assertEqual($p[-XPT_POW_LOW], 1.0);
    testing.assertEqual($p[-XPT_POW_LOW + 10], 1024.0);
    testing.assertEqual($p[-XPT_POW_LOW - 1], 0.5);
}

func testXptV8LongNames() {
    def ds as Dataset init xptRead(xptFixture(XPT_V8_LONG));
    testing.assertEqual($ds.version, "8");
    testing.assertEqual($ds.name, "LONGNAMEDTABLE1");
    testing.assertEqual($ds.label, "Long-name test");
    testing.assertEqual(names($ds), ["patientIdentifier", "visitDate", "c"]);
    def v as Variable init variable($ds, "patientIdentifier");
    testing.assertEqual($v.label, "A label that is clearly longer than forty characters, yes");
    testing.assertEqual($v.format, "LONGFORMATNAME12.");
    testing.assertEqual(variable($ds, "visitDate").format, "DATE9.");
    testing.assertEqual(column($ds, "visitDate"), [21915.0, 22000.5]);
    testing.assertEqual(textColumn($ds, "c"), ["a", "b"]);
    testing.assertEqual(variable($ds, "c").format, "$CHAR1.");
}

func testXptSpecialMissing() {
    def ds as Dataset init xptRead(xptFixture(XPT_V5_SPECIAL));
    testing.assertEqual($ds.name, "SPECIAL");
    testing.assertEqual($ds.label, "Hand made ä");
    testing.assertEqual($ds.missing[0], ["", ".", "._", "", ""]);
    testing.assertEqual($ds.missing[1], ["", ".a", "", "", "."]);
    testing.assertEqual($ds.missing[2], ["", ".z", "", "", ""]);
    testing.assertEqual($ds.missing[3], ["", "._", "", "", "."]);
    testing.assertEqual($ds.numbers[0], [1.0, 0.0, 0.0, -123.456, 0.0]);
    testing.assertEqual(text($ds, "t3", 1), ".a");
    testing.assertEqual(present($ds, "x"), [1.0, -123.456, 0.0]);
    testing.assertEqual(variable($ds, "x").format, "BEST12.");
}

func testXptShortNumbers() {
    # numbers stored in 3, 5 and 2 bytes are padded with zero bytes on
    # the right; the values are what the truncated IBM floats hold
    def ds as Dataset init xptRead(xptFixture(XPT_V5_SPECIAL));
    testing.assertEqual(present($ds, "t3"), [1.5, 100.0, -7.0]);
    testing.assertEqual(
        present($ds, "t5"),
        [3.140625, -0.09999999986030161, 65536.25, 0.0009999999992942321]);
    testing.assertEqual(present($ds, "t2"), [0.5, 2.0, -1.0]);
    # a number's width is its stored size
    def widths as list of int init [];
    for (def v in $ds.variables) {
        if ($v.type == "numeric") {
            $widths[] = $v.width;
        }
    }
    testing.assertEqual($widths, [8, 3, 5, 2]);
}

func testXptEncoding() {
    def data as bytes init xptFixture(XPT_V5_SPECIAL);
    def ds as Dataset init xptRead($data);
    testing.assertEqual(textColumn($ds, "s"), ["café", "€ 5", "Straße", "", "  lead"]);
    testing.assertEqual(variable($ds, "s").label, "Café €");
    testing.assertEqual(variable($ds, "s").width, 8);
    testing.assertEqual(variable($ds, "s").format, "$8.");
    def opts as Options init options();
    $opts.encoding = "ISO-8859-1";
    $ds = readXpt($data, $opts);
    testing.assertEqual($ds.encoding, "iso-8859-1");
    testing.assertEqual(textColumn($ds, "s")[2], "Straße");
    testing.assertEqual(textColumn($ds, "s")[1], "\u0080 5");
}

func testXptV8LabelSection() {
    def ds as Dataset init xptRead(xptFixture(XPT_V8_HAND));
    testing.assertEqual($ds.version, "8");
    testing.assertEqual($ds.name, "HANDMADE8");
    testing.assertEqual($ds.label, "Grüße");
    testing.assertEqual($ds.rowCount, 3);
    testing.assertEqual(names($ds), ["measurementValue", "code"]);
    testing.assertEqual(variable($ds, "measurementValue").label, strings.replicate("M", 50));
    testing.assertEqual(variable($ds, "measurementValue").format, "COMMA10.2");
    testing.assertEqual($ds.numbers[0], [1234.5, 0.0, -0.0001]);
    testing.assertEqual($ds.missing[0], ["", ".m", ""]);
    testing.assertEqual(textColumn($ds, "code"), ["ab", "é", "xyz"]);
}

func testXptTrailingBlankRows() {
    # version 5 cannot tell blank final rows from the record's padding:
    # rows a, b, "", "" read as two rows (as ReadStat reads them)
    def ds as Dataset init xptRead(xptFixture(XPT_V5_BLANK));
    testing.assertEqual($ds.rowCount, 2);
    testing.assertEqual(textColumn($ds, "s"), ["a", "b"]);
    # the version 8 file states its 4 rows in the OBSV8 header
    $ds = xptRead(xptFixture(XPT_V8_BLANK));
    testing.assertEqual($ds.rowCount, 4);
    testing.assertEqual(textColumn($ds, "s"), ["a", "b", "", ""]);
}

# A file written by SAS 9.3 itself (CDISC pilot study, see the fixture):
# every name, label, width and cell as pyreadstat 1.3.8 reads them.
func testXptWrittenBySas() {
    def ds as Dataset init xptRead(xptFixture(XPT_SAS_SUPPDS));
    testing.assertEqual($ds.name, "SUPPDS");
    testing.assertEqual($ds.version, "5");
    testing.assertEqual($ds.rowCount, 3);
    testing.assertEqual(
        names($ds),
        [
            "STUDYID",
            "RDOMAIN",
            "USUBJID",
            "IDVAR",
            "IDVARVAL",
            "QNAM",
            "QLABEL",
            "QVAL",
            "QORIG",
            "QEVAL"
        ]);
    def labels as list of string init [];
    def widths as list of int init [];
    for (def v in $ds.variables) {
        testing.assertEqual($v.type, "string");
        $labels[] = $v.label;
        $widths[] = $v.width;
    }
    testing.assertEqual(
        $labels,
        [
            "Study Identifier",
            "Related Domain Abbreviation",
            "Unique Subject Identifier",
            "Identifying Variable",
            "Identifying Variable Value",
            "Qualifier Variable Name",
            "Qualifier Variable Label",
            "Data Value",
            "Origin",
            "Evaluator"
        ]);
    testing.assertEqual($widths, [12, 2, 11, 8, 200, 8, 40, 200, 200, 200]);
    testing.assertEqual(textColumn($ds, "USUBJID"), ["01-703-1175", "01-705-1382", "01-708-1372"]);
    testing.assertEqual(textColumn($ds, "QVAL"), ["16", "25", "16"]);
    testing.assertEqual(textColumn($ds, "QEVAL"), ["", "", ""]);
    for (def r in 0..3) {
        testing.assertEqual(text($ds, "STUDYID", $r), "CDISCPILOT01");
        testing.assertEqual(text($ds, "RDOMAIN", $r), "DS");
        testing.assertEqual(text($ds, "IDVAR", $r), "DSSEQ");
        testing.assertEqual(text($ds, "IDVARVAL", $r), "1");
        testing.assertEqual(text($ds, "QNAM", $r), "ENTCRIT");
        testing.assertEqual(text($ds, "QLABEL", $r), "PROTOCOL ENTRY CRITERIA NOT MET");
        testing.assertEqual(text($ds, "QORIG", $r), "CRF");
    }
}

func testXptMembers() {
    for (def lines in [XPT_V5_MULTI, XPT_V8_MULTI]) {
        def all as list of Dataset init readXptMembers(xptFixture($lines), options());
        testing.assertEqual(len($all), 2);
        testing.assertEqual($all[0].name, "FIRST");
        testing.assertEqual($all[0].label, "First member");
        testing.assertEqual(column($all[0], "x"), [1.0, 2.0, 3.0]);
        testing.assertEqual($all[1].name, "SECOND");
        testing.assertEqual($all[1].label, "Second member");
        testing.assertEqual(textColumn($all[1], "y"), ["one", "two"]);
        testing.assertEqual($all[1].numbers[1], [10.5, 0.0]);
        testing.assertEqual($all[1].missing[1], ["", "."]);
        testing.assertThrowsArgs("xptRead", [xptFixture($lines)], ERROR_KIND);
    }
    def one as list of Dataset init readXptMembers(xptFixture(XPT_V5_BASIC), options());
    testing.assertEqual(len($one), 1);
    testing.assertEqual($one[0].rowCount, 7);
}

func testXptNoMember() {
    # the three library header records alone: a library of no members
    def data as bytes init xptFixture(XPT_V5_BASIC)[..240];
    testing.assertEqual(readXptMembers($data, options()), []);
    testing.assertThrowsArgs("xptRead", [$data], ERROR_KIND);
}

func testXptMaxCells() {
    def data as bytes init xptFixture(XPT_V5_BASIC);
    def opts as Options init options();
    $opts.maxCells = 35;
    testing.assertEqual(readXpt($data, $opts).rowCount, 7);
    $opts.maxCells = 34;
    try {
        readXpt($data, $opts);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    # the cap counts the cells of every member: 3 + 4
    $data = xptFixture(XPT_V8_MULTI);
    $opts.maxCells = 7;
    testing.assertEqual(len(readXptMembers($data, $opts)), 2);
    $opts.maxCells = 6;
    try {
        readXptMembers($data, $opts);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    $opts.maxCells = 0;
    try {
        readXptMembers($data, $opts);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testXptTruncated() {
    # every cut of a file is an error of kind statfiles, except one at the
    # end of the library header (a library of no members), and a version 5
    # cut at a record boundary inside the data area: that is a shorter file,
    # unless the cut leaves part of a row
    def data as bytes init xptFixture(XPT_V5_BASIC);
    def dataStart as int init xptFind($data, "HEADER RECORD*******OBS ") + 80;
    def shorter as int init 0;
    for (def cut in 0..len($data)) {
        def kind as string init xptKind($data[..$cut]);
        if ($cut == 240) {
            testing.assertEqual($kind, "");
        } elseif ($cut % 80 == 0 and $cut >= $dataStart) {
            testing.assertTrue($kind == "" or $kind == ERROR_KIND);
            if ($kind == "") {
                $shorter = $shorter + 1;
            }
        } else {
            testing.assertEqual($kind, ERROR_KIND);
        }
    }
    testing.assertEqual($shorter, 1);
    # version 8 states its row count, so every other cut is an error; a cut
    # at the second member's header leaves a file of one member
    $data = xptFixture(XPT_V8_MULTI);
    def second as int init binary.indexOf($data, encoding.encode("ascii", "MEMBV8"), 300) - 20;
    for (def cut in 0..len($data)) {
        def kind as string init xptKind($data[..$cut]);
        if ($cut == 240 or $cut == $second) {
            testing.assertEqual($kind, "");
        } else {
            testing.assertEqual($kind, ERROR_KIND);
        }
    }
}

func testXptCorrupt() {
    def data as bytes init xptFixture(XPT_V5_BASIC);
    testing.assertEqual(xptKind($data), "");
    # first NAMESTR at 640: type, length, position
    testing.assertEqual(xptKind(xptPatch($data, 641, "\u0003")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, 645, "\t")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, 645, "\u0001")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, 640 + 86, "\u0001")), ERROR_KIND);
    # member header: NAMESTR length; NAMESTR header: variable count
    testing.assertEqual(xptKind(xptPatch($data, 240 + 74, "0150")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, 560 + 54, "00x5")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, 560 + 54, "0006")), ERROR_KIND);
    # header names, a version 8 header in a version 5 file
    testing.assertEqual(xptKind(xptPatch($data, 240 + 20, "MEMBV8  ")), ERROR_KIND);
    testing.assertEqual(
        xptKind(xptPatch($data, xptFind($data, "OBS     HEADER"), "OBSV8   ")),
        ERROR_KIND);
    # padding after the last row that is not blank, a stray byte
    testing.assertEqual(xptKind(xptPatch($data, len($data) - 1, "x")), ERROR_KIND);
    testing.assertEqual(xptKind(binary.concat($data, binary.make(1, 32))), ERROR_KIND);
    testing.assertEqual(xptKind(binary.make(len($data), 32)), ERROR_KIND);
}

func testXptCorruptV8() {
    def data as bytes init xptFixture(XPT_V8_BLANK);
    def obs as int init xptFind($data, "OBSV8");
    def blanks as string init strings.replicate(" ", 31);
    testing.assertEqual(xptKind(xptPatch($data, $obs - 20 + 48, "4" + $blanks)), "");
    testing.assertEqual(xptKind(xptPatch($data, $obs - 20 + 48, "81" + $blanks)), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, $obs - 20 + 48, "1" + $blanks)), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, $obs - 20 + 48, "4x" + $blanks)), ERROR_KIND);
    # LABELV9 records: variable number, then a name length past the end
    $data = xptFixture(XPT_V8_LONG);
    def labels as int init xptFind($data, "HEADER RECORD*******LABELV9");
    testing.assertEqual(xptKind($data), "");
    testing.assertEqual(xptKind(xptPatch($data, $labels + 81, "\u0009")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, $labels + 82, "\u007f")), ERROR_KIND);
    testing.assertEqual(xptKind(xptPatch($data, $labels + 48, "x")), ERROR_KIND);
}

func testXptBadEncoding() {
    def opts as Options init options();
    $opts.encoding = "klingon";
    try {
        readXpt(xptFixture(XPT_V5_BASIC), $opts);
        missed();
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}
