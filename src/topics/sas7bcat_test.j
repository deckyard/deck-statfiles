# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - white-box tests for the sas7bcat topic. Spliced into
# statfiles_test.j via include, after the sas7bdat overlay (its fixtures and
# helpers). Every catalog's labels match pyreadstat 1.3.8 (ReadStat).

/**
 * Read a sample catalog with the default options.
 *
 * @param lines {list of string} one of the SAS7_CATALOG_* constants
 * @return {map of string to map of string to string} its formats
 */
func sas7cRead(lines as list of string) {
    return readSas7bcat(sas7Fixture($lines), options());
}

/**
 * The kind of the error reading a catalog throws, `""` when it reads.
 *
 * @param data {bytes} the catalog
 * @param opts {Options} the options
 * @return {string} the kind
 */
func sas7cErrorKind(data as bytes, opts as Options) {
    try {
        readSas7bcat($data, $opts);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

func testSas7CatalogTagged() {
    def formats as map of string to map of string to string init sas7cRead(SAS7_CATALOG_TAGGED);
    testing.assertEqual($formats, {"XFMT": {".a": "Apple", ".z": "Zebra"}});
    def ds as Dataset init withSasLabels(sas7Read(SAS7_FILE_TAGGED), $formats);
    testing.assertEqual(variable($ds, "x").valueLabels, {".a": "Apple", ".z": "Zebra"});
    testing.assertEqual(labelOf($ds, "x", 0), "");
    testing.assertEqual(labelOf($ds, "x", 5), "Apple");
    testing.assertEqual(labelOf($ds, "x", 6), "");
    testing.assertEqual(labelOf($ds, "x", 7), "Zebra");
}

func testSas7CatalogHadley() {
    def formats as map of string to map of string to string init sas7cRead(SAS7_CATALOG_HADLEY);
    testing.assertEqual(
        $formats,
        {"$GENDER": {"f": "Female", "m": "Male"}, "WORKSHOP": {"1": "R", "2": "SAS"}});
    def ds as Dataset init withSasLabels(sas7Read(SAS7_FILE_HADLEY), $formats);
    testing.assertEqual(labelOf($ds, "workshop", 0), "R");
    testing.assertEqual(labelOf($ds, "workshop", 1), "SAS");
    testing.assertEqual(labelOf($ds, "gender", 0), "Female");
    testing.assertEqual(labelOf($ds, "gender", 4), "Male");
    testing.assertEqual(labelOf($ds, "gender", 3), "");
    testing.assertEqual(variable($ds, "q1").valueLabels, {});
    testing.assertTrue(strings.contains(toCsv($ds, true), "1,R,Female,"));
    # a character format is not given to a numeric variable, nor a numeric
    # one to a string variable
    $ds = withSasLabels(sas7Read(SAS7_FILE_HADLEY), {});
    testing.assertEqual(variable($ds, "gender").valueLabels, {});
    $ds.variables[indexOf($ds, "id")].format = "$GENDER.";
    $ds.variables[indexOf($ds, "q1")].format = "WORKSHOP.";
    $ds.variables[indexOf($ds, "gender")].format = "WORKSHOP.";
    $ds = withSasLabels($ds, $formats);
    testing.assertEqual(variable($ds, "id").valueLabels, {});
    testing.assertEqual(variable($ds, "gender").valueLabels, {});
    testing.assertEqual(variable($ds, "q1").valueLabels, {"1": "R", "2": "SAS"});
}

func testSas7CatalogMissing() {
    # a 64-bit catalog whose value is the special missing .A
    def formats as map of string to map of string to string init sas7cRead(SAS7_CATALOG_MISSING);
    testing.assertEqual($formats, {"A": {".a": "missing"}});
    def ds as Dataset init withSasLabels(sas7Read(SAS7_FILE_MISSING), $formats);
    testing.assertEqual(variable($ds, "var1").format, "A.");
    testing.assertEqual(labelOf($ds, "var1", 0), "missing");
}

func testSas7CatalogOther() {
    # long character values (moved one byte right) and an OTHER label,
    # which is left out
    testing.assertEqual(
        sas7cRead(SAS7_CATALOG_OTHER),
        {"$YESNO": {"Yes, I could not agree more": "True", "No, not really": "False"}});
}

func testSas7CatalogEncoding() {
    def data as bytes init sas7Fixture(SAS7_CATALOG_UTF8);
    testing.assertEqual(sas7cErrorKind($data, options()), ERROR_KIND);
    def opts as Options init options();
    $opts.encoding = "utf-8";
    testing.assertEqual(readSas7bcat($data, $opts), {"XFMT": {".a": "Áple", ".z": "Zebra"}});
}

func testSas7CatalogRanges() {
    # the character range 'a'-<'g' and the numeric range 1-<2 are left out,
    # whatever their ends; the range's label is a type-9 record (32 bytes of
    # text, its length in bytes 2-3), stepped over to reach the next label
    testing.assertEqual(
        sas7cRead(SAS7_CATALOG_RULES),
        {"$GENDER": {"m": "Male"}, "WORKSHOP": {"2": "SAS"}});
    def ds as Dataset init withSasLabels(sas7Read(SAS7_FILE_HADLEY), sas7cRead(SAS7_CATALOG_RULES));
    testing.assertEqual(labelOf($ds, "workshop", 0), "");
    testing.assertEqual(labelOf($ds, "workshop", 1), "SAS");
    testing.assertEqual(labelOf($ds, "gender", 0), "");
    testing.assertEqual(labelOf($ds, "gender", 4), "Male");
}

func testSas7CatalogLinks() {
    # WORKSHOP's block is one link at page 4, offset 271 (file offset
    # 13583): pointing it at itself makes a chain without end
    def data as bytes init sas7Fixture(SAS7_CATALOG_HADLEY);
    testing.assertEqual(sas7cErrorKind($data, options()), "");
    testing.assertEqual(
        sas7cErrorKind(sas7Patch($data, 13583, [4, 0, 0, 0, 15, 1]), options()),
        ERROR_KIND);
    # a next link past the last page
    testing.assertEqual(
        sas7cErrorKind(sas7Patch($data, 13583, [5, 0, 0, 0, 15, 1]), options()),
        ERROR_KIND);
}

func testSas7CatalogLimits() {
    # the catalog's size counts against maxBytes, checked before parsing
    def data as bytes init sas7Fixture(SAS7_CATALOG_HADLEY);
    def opts as Options init options();
    $opts.maxBytes = len($data);
    testing.assertEqual(sas7cErrorKind($data, $opts), "");
    $opts.maxBytes = len($data) - 1;
    testing.assertEqual(sas7cErrorKind($data, $opts), "limit");
    # every label read counts against maxCells: 2 + 2 here
    $opts = options();
    $opts.maxCells = 4;
    testing.assertEqual(sas7cErrorKind($data, $opts), "");
    $opts.maxCells = 3;
    testing.assertEqual(sas7cErrorKind($data, $opts), "limit");
    # ranges and OTHER count too, though left out of the result: 2 + 2
    # labels and 2 + OTHER
    $opts.maxCells = 4;
    testing.assertEqual(sas7cErrorKind(sas7Fixture(SAS7_CATALOG_RULES), $opts), "");
    $opts.maxCells = 3;
    testing.assertEqual(sas7cErrorKind(sas7Fixture(SAS7_CATALOG_RULES), $opts), "limit");
    testing.assertEqual(sas7cErrorKind(sas7Fixture(SAS7_CATALOG_OTHER), $opts), "");
    $opts.maxCells = 2;
    testing.assertEqual(sas7cErrorKind(sas7Fixture(SAS7_CATALOG_OTHER), $opts), "limit");
}

func testSas7CatalogEmptyFormat() {
    # $YESNO's two values made ranges (entry type byte 6 set to 4): only
    # its OTHER label is left, so the format is left out, not an empty map
    def data as bytes init sas7Fixture(SAS7_CATALOG_OTHER);
    testing.assertEqual(
        readSas7bcat(sas7Patch($data, 20751, [4]), options()),
        {"$YESNO": {"No, not really": "False"}});
    testing.assertEqual(
        readSas7bcat(sas7Patch(sas7Patch($data, 20751, [4]), 20708, [4]), options()),
        {});
}

func testSas7CatalogKeys() {
    # positive values are stored with the sign bit set, negative ones with
    # every bit flipped
    testing.assertEqual(sas7cKey(sas7Pattern(0xBFF00000, 0)), "1");
    testing.assertEqual(sas7cKey(sas7Pattern(0xC0040000, 0)), "2.5");
    testing.assertEqual(sas7cKey(sas7Pattern(0x3FFFFFFF, 0xFFFFFFFF)), "-2");
    testing.assertEqual(sas7cKey(sas7Pattern(0x000002FF, 0xFFFFFFFF)), ".a");
    testing.assertEqual(sas7cKey(sas7Pattern(0x00005AFF, 0xFFFFFFFF)), ".z");
    testing.assertEqual(sas7cKey(sas7Pattern(0x000000FF, 0xFFFFFFFF)), "._");
    testing.assertEqual(sas7cKey(sas7Pattern(0x000001FF, 0xFFFFFFFF)), ".");
}

func testSas7FormatName() {
    testing.assertEqual(sasFormatName("$GENDER6."), "$GENDER");
    testing.assertEqual(sasFormatName("WORKSHOP."), "WORKSHOP");
    testing.assertEqual(sasFormatName("yymmdd10."), "YYMMDD");
    testing.assertEqual(sasFormatName("E8601DA10."), "E8601DA");
    testing.assertEqual(sasFormatName("BEST12.2"), "BEST");
    testing.assertEqual(sasFormatName("F8_2."), "F8_");
    testing.assertEqual(sasFormatName("8.2"), "");
    testing.assertEqual(sasFormatName("$8."), "");
    testing.assertEqual(sasFormatName(""), "");
    testing.assertEqual(sasFormatName("DATE"), "");
}

func testSas7CatalogErrors() {
    def data as bytes init sas7Fixture(SAS7_CATALOG_HADLEY);
    testing.assertEqual(sas7cErrorKind(sas7Fixture(SAS7_FILE_HADLEY), options()), ERROR_KIND);
    testing.assertEqual(sas7cErrorKind(binary.make(4096), options()), ERROR_KIND);
    testing.assertEqual(
        sas7cErrorKind(binary.slice($data, 0, len($data) - 1), options()),
        ERROR_KIND);
    # a catalog of one page has no index
    def one as bytes init sas7Patch(binary.slice($data, 0, 1024 + 4096), 208, [1, 0, 0, 0]);
    testing.assertEqual(sas7cErrorKind($one, options()), ERROR_KIND);
    # every byte of the pages holding the blocks, inverted: an error of
    # kind statfiles, or a catalog that still reads
    for (def at in 1024 + 3 * 4096..len($data)) {
        if ($at % 3 != 0) {
            continue;
        }
        def kind as string init sas7cErrorKind(
            sas7Patch($data, $at, [$data[$at] ^ 0xFF]),
            options());
        testing.assertTrue($kind == "" or $kind == ERROR_KIND);
    }
}
