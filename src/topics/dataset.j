# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# statfiles - the dataset topic: the result types, options, format detection
# and dispatch, the cell and column accessors, CSV output, and the helpers
# the format readers share. Spliced into statfiles.j via include.

/** The `kind` of every error the deck throws for a malformed file or a bad argument. */
export def const ERROR_KIND as string init "statfiles";

/** The most cells (rows times variables) a reader takes unless `Options.maxCells` says otherwise. */
export def const DEFAULT_MAX_CELLS as int init 2000000;

/** The most bytes compressed SPSS cases (`.zsav`, bytecode) may unpack to unless `Options.maxBytes` says otherwise. */
export def const DEFAULT_MAX_BYTES as int init 268435456;

/** The missing code of a system-missing cell: Stata's and SAS's `.`, SPSS's SYSMIS. */
export def const MISSING_SYSTEM as string init ".";

/** The missing code of a value SPSS declares missing; the value itself is kept. */
export def const MISSING_USER as string init "user";

/** The lower end of an SPSS missing range declared `LO THRU x`. */
export def const LOWEST as float init -1.7976931348623157e308;

/** The upper end of an SPSS missing range declared `x THRU HI`. */
export def const HIGHEST as float init 1.7976931348623157e308;

/**
 * A variable (column) of a data file.
 *
 * @field name {string} the variable's name, as stored
 * @field label {string} its label, `""` if none
 * @field type {string} `numeric` or `string`
 * @field storage {string} the file's own storage type: Stata `byte`, `int`,
 *   `long`, `float`, `double`, `str<n>` or `strL`; SPSS and SAS `numeric` or
 *   `string`
 * @field width {int} the bytes a value takes in the file: a string
 *   variable's width (0 for a Stata `strL`); a number's stored size, Stata
 *   1 (`byte`), 2 (`int`), 4 (`long`, `float`) or 8 (`double`), SPSS
 *   `.sav` / `.zsav` 8, SAS `.sas7bdat` 3 to 8, XPORT 2 to 8; 0 for a number
 *   of a `.por`, a text format
 * @field format {string} the display format as the file writes it, such as
 *   `%9.0g`, `F8.2` or `DATE9.`; `""` if none
 * @field valueLabels {map of string to string} the value labels, keyed by
 *   the value as `valueKey` writes it (a string value without trailing blanks)
 * @field missingValues {list of string} values SPSS declares missing, as
 *   `valueKey` writes them; empty for Stata and SAS
 * @field missingRange {list of float} an SPSS declared missing range
 *   `[low, high]` (`LOWEST` / `HIGHEST` for an open end); empty if none
 */
export def struct Variable {
    name as string,
    label as string,
    type as string,
    storage as string,
    width as int,
    format as string,
    valueLabels as map of string to string,
    missingValues as list of string,
    missingRange as list of float
};

/**
 * The contents of a data file, stored by column: entry `i` of `numbers`,
 * `texts` and `missing` belongs to `variables[i]`, and each holds one entry
 * per row.
 *
 * @field format {string} `dta`, `sav`, `zsav`, `por`, `xpt` or `sas7bdat`
 * @field version {string} the format's version: the Stata release format
 *   such as `118`, the XPORT version `5` or `8`, the SAS release that wrote
 *   a sas7bdat file such as `9.0401M5`, `""` for SPSS
 * @field name {string} the dataset's name where the format has one (an
 *   XPORT member, a SAS data set), else `""`
 * @field label {string} the dataset's label, `""` if none
 * @field encoding {string} the character set the text was decoded from
 * @field rowCount {int} the number of rows
 * @field variables {list of Variable} the variables, in file order
 * @field numbers {list of list of float} a numeric variable's values (0.0
 *   where missing); an empty list for a string variable
 * @field texts {list of list of string} a string variable's values: Stata's
 *   as stored (trailing blanks kept, a `str<n>` cut at its first NUL), SPSS's
 *   and SAS's without trailing blanks (their padding); an empty list for a
 *   numeric variable
 * @field missing {list of list of string} each cell's missing code, `""`
 *   when present
 */
export def struct Dataset {
    format as string,
    version as string,
    name as string,
    label as string,
    encoding as string,
    rowCount as int,
    variables as list of Variable,
    numbers as list of list of float,
    texts as list of list of string,
    missing as list of list of string
};

/**
 * How a file is read.
 *
 * @field encoding {string} the character set of the text, overriding what
 *   the file declares; `""` takes the file's own, or the format's default
 *   (`windows-1252` for Stata before 118 and for SAS, `utf-8` otherwise)
 * @field maxCells {int} the most cells (rows times variables) read, and the
 *   most value labels `readSas7bcat` reads; kind `"limit"` beyond
 * @field maxBytes {int} the most bytes compressed SPSS cases unpack to,
 *   both the zlib blocks of a `.zsav` and the bytecode of a `.sav` or
 *   `.zsav` in the uncompressed layout, the rows of a compressed
 *   `.sas7bdat` unpack to, and the largest `.sas7bcat`; kind `"limit"`
 *   beyond
 */
export def struct Options {
    encoding as string,
    maxCells as int,
    maxBytes as int
};

/**
 * The default options: the file's own encoding, `DEFAULT_MAX_CELLS` and
 * `DEFAULT_MAX_BYTES`.
 *
 * @return {Options} the options
 */
export func options() {
    return Options{encoding: "", maxCells: DEFAULT_MAX_CELLS, maxBytes: DEFAULT_MAX_BYTES};
}

/**
 * Throw a statfiles error.
 *
 * The message carries no `statfiles: ` prefix: the kind already says where
 * the error comes from.
 *
 * @param message {string} what is wrong
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: $message};
}

/**
 * Throw a `"limit"` error.
 *
 * @param message {string} which cap was reached
 */
func failLimit(message as string) {
    throw Error{kind: "limit", message: $message};
}

/**
 * Refuse options a reader cannot work with, and a table over the cell cap.
 *
 * @param opts {Options} the options
 * @param rows {int} the rows the file declares
 * @param variables {int} the variables it declares
 */
func checkSize(opts as Options, rows as int, variables as int) {
    if ($opts.maxCells < 1 or $opts.maxBytes < 1) {
        fail("maxCells and maxBytes are at least 1");
    }
    if ($rows < 0 or $variables < 0) {
        fail("the file declares a negative number of rows or variables");
    }
    if ($variables > 0 and $rows > $opts.maxCells / $variables) {
        failLimit(io.sprintf(
            "%d rows of %d variables is over %d cells",
            $rows,
            $variables,
            $opts.maxCells));
    }
}

/**
 * Throw unless `count` bytes from `offset` lie inside `data`.
 *
 * @param data {bytes} the file
 * @param offset {int} the first byte
 * @param count {int} how many bytes are needed
 * @param what {string} what is read there, for the message
 */
func need(data as bytes, offset as int, count as int, what as string) {
    if ($offset < 0 or $count < 0 or $offset + $count > len($data)) {
        fail(io.sprintf("the file ends inside %s (offset %d)", $what, $offset));
    }
}

/**
 * The bytes before the first NUL.
 *
 * @param b {bytes} the field
 * @return {bytes} the bytes up to, not including, the first NUL
 */
func untilNul(b as bytes) {
    def at as int init binary.indexOf($b, binary.make(1));
    if ($at < 0) {
        return $b;
    }
    return $b[..$at];
}

/**
 * Decode text in a character set and drop its trailing blanks and NULs.
 *
 * @param b {bytes} the text
 * @param charset {string} an `encoding` codec name, or `utf-8`
 * @return {string} the text
 */
func decodeText(b as bytes, charset as string) {
    def end as int init len($b);
    while ($end > 0 and ($b[$end - 1] == 32 or $b[$end - 1] == 0)) {
        $end = $end - 1;
    }
    if ($end < len($b)) {
        $b = $b[..$end];
    }
    return decodeBytes($b, $charset);
}

/**
 * Decode text in a character set as it is, blanks and NULs included.
 *
 * @param b {bytes} the text
 * @param charset {string} an `encoding` codec name, or `utf-8`
 * @return {string} the text
 */
func decodeBytes(b as bytes, charset as string) {
    def s as string;
    if ($charset == "utf-8") {
        try {
            $s = encoding.decode("utf-8", $b);
        } catch (e) {
            fail("text that is not valid UTF-8 (set Options.encoding if the file is in another character set)");
        }
    } else {
        try {
            $s = encoding.decode($charset, $b);
        } catch (e) {
            fail("text with a byte " + $charset +
                " does not have (set Options.encoding if the file is in another character set)");
        }
    }
    return $s;
}

/**
 * The `encoding` codec name for a character set name a file declares, such
 * as `UTF-8`, `windows-1252`, `CP1252`, `ISO-8859-1` or `latin1`.
 *
 * @param name {string} the declared name
 * @return {string} the codec name; throws for a character set the
 *   `encoding` library lacks
 */
func charsetName(name as string) {
    def n as string init strings.replace(strings.lower(strings.trim($name)), "_", "-");
    if ($n == "utf-8" or $n == "utf8") {
        return "utf-8";
    }
    if ($n == "us-ascii" or $n == "ascii" or $n == "ansi-x3.4-1968") {
        return "ascii";
    }
    if ($n == "latin1" or $n == "latin-1" or $n == "iso8859-1") {
        return "iso-8859-1";
    }
    def m as regex.Match init regex.find('^(?:windows-?|cp-?|ms-?)(125[0-8])$', $n);
    if ($m.start >= 0) {
        return "windows-" + $m.groups[0];
    }
    $m = regex.find('^iso-?8859-?([0-9]{1,2})$', $n);
    if ($m.start >= 0) {
        $n = "iso-8859-" + $m.groups[0];
    }
    if (lists.contains(encoding.codecs(), $n)) {
        return $n;
    }
    fail("the character set " + $name + " is not supported (set Options.encoding)");
    return "";
}

/**
 * The text a value has as a value-label key, a missing value or a CSV cell:
 * an integral number without a decimal point, any other the shortest form
 * that reads back the same.
 *
 * @param x {float} the value
 * @return {string} the text, such as `3`, `-1` or `2.5`
 * @example
 *   statfiles.valueKey(3.0);   # "3"
 */
export func valueKey(x as float) {
    if (math.abs($x) < 9007199254740992.0 and $x == convert.toFloat(math.floor($x))) {
        return convert.toString(math.floor($x));
    }
    return convert.toString($x);
}

/**
 * The format of a file, from its first bytes.
 *
 * @param data {bytes} the file, or at least its first 512 bytes
 * @return {string} `dta`, `sav`, `zsav`, `por`, `xpt`, `sas7bdat`, the
 *   SAS format catalog `sas7bcat` (which `read` refuses), or `""` when it
 *   is none of them
 */
export func detect(data as bytes) {
    if (looksLikeDta($data)) {
        return "dta";
    }
    if (binary.startsWith($data, encoding.encode("utf-8", "$FL2"))) {
        return "sav";
    }
    if (binary.startsWith($data, encoding.encode("utf-8", "$FL3"))) {
        return "zsav";
    }
    if (looksLikeXpt($data)) {
        return "xpt";
    }
    if (looksLikeSas7bdat($data)) {
        return "sas7bdat";
    }
    if (looksLikeSas7bcat($data)) {
        return "sas7bcat";
    }
    if (looksLikePor($data)) {
        return "por";
    }
    return "";
}

/**
 * Read a data file of any supported format with the default options.
 *
 * @param data {bytes} the file
 * @return {Dataset} its contents
 * @throws {Error} kind `"statfiles"` for an unknown format or a malformed
 *   file, `"limit"` over a cap
 * @example
 *   def ds as statfiles.Dataset init statfiles.read(fs.readBytes("trial.dta"));
 */
export func read(data as bytes) {
    return readWith($data, options());
}

/**
 * Read a data file of any supported format.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {Dataset} its contents
 * @throws {Error} kind `"statfiles"` for an unknown format or a malformed
 *   file, `"limit"` over a cap
 */
export func readWith(data as bytes, opts as Options) {
    def f as string init detect($data);
    if ($f == "dta") {
        return readDta($data, $opts);
    }
    if ($f == "sav" or $f == "zsav") {
        return readSav($data, $opts);
    }
    if ($f == "por") {
        return readPor($data, $opts);
    }
    if ($f == "xpt") {
        return readXpt($data, $opts);
    }
    if ($f == "sas7bdat") {
        return readSas7bdat($data, $opts);
    }
    if ($f == "sas7bcat") {
        fail("a SAS format catalog, not a data set: readSas7bcat reads it");
    }
    fail("not a Stata, SPSS or SAS file");
}

/**
 * The position of a variable.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name, exactly as stored
 * @return {int} its index in `variables`, -1 if there is none
 */
export func indexOf(ds as Dataset, name as string) {
    def i as int init 0;
    for (def v in $ds.variables) {
        if ($v.name == $name) {
            return $i;
        }
        $i = $i + 1;
    }
    return -1;
}

/**
 * The index of a variable, or an error naming it.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {int} its index
 */
func indexOrFail(ds as Dataset, name as string) {
    def i as int init indexOf($ds, $name);
    if ($i < 0) {
        fail("no variable " + $name);
    }
    return $i;
}

/**
 * The index of a numeric variable, or an error.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {int} its index
 */
func numericIndex(ds as Dataset, name as string) {
    def i as int init indexOrFail($ds, $name);
    if ($ds.variables[$i].type != "numeric") {
        fail("the variable " + $name + " holds strings, not numbers");
    }
    return $i;
}

/**
 * Throw unless a row number is inside the dataset.
 *
 * @param ds {Dataset} the dataset
 * @param row {int} the row, from 0
 */
func checkRow(ds as Dataset, row as int) {
    if ($row < 0 or $row >= $ds.rowCount) {
        fail(io.sprintf("row %d is not in 0 to %d", $row, $ds.rowCount - 1));
    }
}

/**
 * One variable.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {Variable} the variable
 * @throws {Error} kind `"statfiles"` if there is no such variable
 */
export func variable(ds as Dataset, name as string) {
    return $ds.variables[indexOrFail($ds, $name)];
}

/**
 * The names of the variables, in file order.
 *
 * @param ds {Dataset} the dataset
 * @return {list of string} the names
 */
export func names(ds as Dataset) {
    def out as list of string init [];
    for (def v in $ds.variables) {
        $out[] = $v.name;
    }
    return $out;
}

/**
 * Every value of a numeric variable, for `stats` and `linalg`. Strict: a
 * missing cell is an error, so the values stay aligned with the rows; use
 * `present` to leave the missing ones out.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {list of float} one value per row
 * @throws {Error} kind `"statfiles"` for a string variable or a missing cell
 */
export func column(ds as Dataset, name as string) {
    def i as int init numericIndex($ds, $name);
    def miss as list of string init $ds.missing[$i];
    def r as int init 0;
    for (def code in $miss) {
        if ($code != "") {
            fail(io.sprintf("%s is missing (%s) in row %d", $name, $code, $r));
        }
        $r = $r + 1;
    }
    return $ds.numbers[$i];
}

/**
 * The values of a numeric variable that are not missing, in row order.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {list of float} the present values
 * @throws {Error} kind `"statfiles"` for a string variable
 */
export func present(ds as Dataset, name as string) {
    def i as int init numericIndex($ds, $name);
    def nums as list of float init $ds.numbers[$i];
    def miss as list of string init $ds.missing[$i];
    def out as list of float init [];
    def r as int init 0;
    for (def code in $miss) {
        if ($code == "") {
            $out[] = $nums[$r];
        }
        $r = $r + 1;
    }
    return $out;
}

/**
 * Every value of a string variable, without trailing blanks.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @return {list of string} one value per row
 * @throws {Error} kind `"statfiles"` for a numeric variable
 */
export func textColumn(ds as Dataset, name as string) {
    def i as int init indexOrFail($ds, $name);
    if ($ds.variables[$i].type != "string") {
        fail("the variable " + $name + " holds numbers, not strings");
    }
    return $ds.texts[$i];
}

/**
 * The missing code of one cell.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @param row {int} the row, from 0
 * @return {string} `""` when present, else `.`, `.a` to `.z`, `._` or `user`
 */
export func missingCode(ds as Dataset, name as string, row as int) {
    def i as int init indexOrFail($ds, $name);
    checkRow($ds, $row);
    return $ds.missing[$i][$row];
}

/**
 * Whether one cell is missing, for any reason.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @param row {int} the row, from 0
 * @return {bool} true when missing
 */
export func isMissing(ds as Dataset, name as string, row as int) {
    return missingCode($ds, $name, $row) != "";
}

/**
 * One numeric cell. A value SPSS declares missing is returned; any other
 * missing cell is an error.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @param row {int} the row, from 0
 * @return {float} the value
 */
export func number(ds as Dataset, name as string, row as int) {
    def i as int init numericIndex($ds, $name);
    checkRow($ds, $row);
    def code as string init $ds.missing[$i][$row];
    if ($code != "" and $code != MISSING_USER) {
        fail(io.sprintf("%s is missing (%s) in row %d", $name, $code, $row));
    }
    return $ds.numbers[$i][$row];
}

/**
 * One cell as text: a string as stored, a number as `valueKey` writes it,
 * a missing number as its missing code (a value SPSS declares missing as
 * the value).
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @param row {int} the row, from 0
 * @return {string} the text
 */
export func text(ds as Dataset, name as string, row as int) {
    def i as int init indexOrFail($ds, $name);
    checkRow($ds, $row);
    return cellText($ds, $i, $row);
}

/**
 * The text of a cell by index, as `text` describes it.
 *
 * @param ds {Dataset} the dataset
 * @param i {int} the variable's index
 * @param row {int} the row
 * @return {string} the text
 */
func cellText(ds as Dataset, i as int, row as int) {
    if ($ds.variables[$i].type == "string") {
        return $ds.texts[$i][$row];
    }
    def code as string init $ds.missing[$i][$row];
    if ($code != "" and $code != MISSING_USER) {
        return $code;
    }
    return valueKey($ds.numbers[$i][$row]);
}

/**
 * The value label of one cell.
 *
 * @param ds {Dataset} the dataset
 * @param name {string} the variable's name
 * @param row {int} the row, from 0
 * @return {string} the label, `""` when the value has none
 */
export func labelOf(ds as Dataset, name as string, row as int) {
    def i as int init indexOrFail($ds, $name);
    checkRow($ds, $row);
    def key as string init cellText($ds, $i, $row);
    def labels as map of string to string init $ds.variables[$i].valueLabels;
    if (maps.has($labels, $key)) {
        return $labels[$key];
    }
    return "";
}

/**
 * The dataset as CSV (RFC 4180): a header row of variable names, then one
 * record per row. A missing number is an empty field (its code is lost;
 * `missingCode` keeps it), a value SPSS declares missing is written as the
 * value.
 *
 * @param ds {Dataset} the dataset
 * @param labels {bool} write a value's label instead of the value where it
 *   has one
 * @return {string} the CSV text
 */
export func toCsv(ds as Dataset, labels as bool) {
    def out as list of list of string init [names($ds)];
    for (def r in 0..$ds.rowCount) {
        def rec as list of string init [];
        for (def i in 0..len($ds.variables)) {
            def code as string init $ds.missing[$i][$r];
            def cell as string init "";
            if ($code == "" or $code == MISSING_USER) {
                $cell = cellText($ds, $i, $r);
                if ($labels and maps.has($ds.variables[$i].valueLabels, $cell)) {
                    $cell = $ds.variables[$i].valueLabels[$cell];
                }
            }
            $rec[] = $cell;
        }
        $out[] = $rec;
    }
    return csv.format($out);
}
