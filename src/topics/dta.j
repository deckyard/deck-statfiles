# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - the dta topic: Stata .dta, the released formats 104 to 119.
# Spliced into statfiles.j via include. Formats 104 to 115 have a fixed
# binary header; 117 to 119 wrap their sections in tags (`<stata_dta>`).
# Characteristics, notes, the sort order and the timestamp are skipped.

use linalg;
use stats;

# The first bytes of a tagged (117 and later) file.
def const DTA_TAGGED as string init "<stata_dta><header><release>";

# Extended missing value letters: `.a` is 1, `.z` 26.
def const DTA_LETTERS as string init "abcdefghijklmnopqrstuvwxyz";

# The largest nonmissing float (0x7effffff) and its missing base 2^127.
def const DTA_FLOAT_MAX as float init 1.7014117331926443e38;
def const DTA_FLOAT_DOT as float init 1.7014118346046923e38;

# The largest nonmissing double (0x7fdfffffffffffff) and its missing base 2^1023.
def const DTA_DOUBLE_MAX as float init 8.988465674311579e307;
def const DTA_DOUBLE_DOT as float init 8.98846567431158e307;

# A double `.` in formats 104 and 105: 2^333.
def const DTA_OLD_DOUBLE_DOT as float init 1.7498005798264095e100;

# Type codes, normalised to those of format 117: 1 to 2045 are strN.
def const DTA_STRL as int init 32768;
def const DTA_DOUBLE as int init 65526;
def const DTA_FLOAT as int init 65527;
def const DTA_LONG as int init 65528;
def const DTA_INT as int init 65529;
def const DTA_BYTE as int init 65530;

# The most rows one bulk number read takes.
def const DTA_CHUNK as int init 1000000;

/**
 * What the header and descriptors of a .dta file say, with the offsets of
 * its data and value labels.
 *
 * @field release {int} the format, such as 118
 * @field order {string} `le` or `be`
 * @field charset {string} the character set of the text
 * @field rows {int} the observations
 * @field label {string} the dataset label
 * @field types {list of int} each variable's type code, as format 117 numbers them
 * @field names {list of string} the variable names
 * @field formats {list of string} the display formats
 * @field labelNames {list of string} each variable's value label name
 * @field varLabels {list of string} the variable labels
 * @field dataAt {int} the offset of the first record
 * @field after {int} the offset after the last record
 * @field offsets {list of int} the map of a tagged file (14 offsets), else empty
 */
def struct DtaHead {
    release as int,
    order as string,
    charset as string,
    rows as int,
    label as string,
    types as list of int,
    names as list of string,
    formats as list of string,
    labelNames as list of string,
    varLabels as list of string,
    dataAt as int,
    after as int,
    offsets as list of int
};

/**
 * What follows the data of a file.
 *
 * @field strls {map of string to string} the strLs, keyed `v:o`
 * @field labels {map of string to map of string to string} the value label
 *   tables by name
 */
def struct DtaTail {
    strls as map of string to string,
    labels as map of string to map of string to string
};

/**
 * One decoded column.
 *
 * @field numbers {list of float} the values of a numeric column
 * @field texts {list of string} the values of a string column
 * @field missing {list of string} each cell's missing code
 */
def struct DtaColumn {
    numbers as list of float,
    texts as list of string,
    missing as list of string
};

/**
 * Whether the first bytes are those of this format.
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikeDta(data as bytes) {
    if (binary.startsWith($data, convert.bytesFromString("utf-8", DTA_TAGGED))) {
        return true;
    }
    if (len($data) < 4) {
        return false;
    }
    return dtaOldRelease($data[0]) and ($data[1] == 1 or $data[1] == 2) and $data[2] == 1;
}

/**
 * Whether a first byte is a released format before 117.
 *
 * @param r {int} the byte
 * @return {bool} true for 104, 105, 108, 110, 111, 113, 114 and 115
 */
func dtaOldRelease(r as int) {
    return $r == 104 or $r == 105 or $r == 108 or $r == 110 or $r == 111 or $r == 113 or
        $r == 114 or $r == 115;
}

/**
 * Read a Stata .dta file, formats 104 to 119, in either byte order.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {Dataset} its contents
 * @throws {Error} kind `"statfiles"` for a malformed file, `"limit"` over a cap
 * @example
 *   def ds as statfiles.Dataset init statfiles.readDta(fs.readBytes("auto.dta"), statfiles.options());
 */
export func readDta(data as bytes, opts as Options) {
    if (binary.startsWith($data, convert.bytesFromString("utf-8", DTA_TAGGED))) {
        def head as DtaHead init dtaTaggedHead($data, $opts);
        def tail as DtaTail init dtaTaggedTail($data, $head);
        return dtaBuild($data, $head, $tail);
    }
    if (len($data) == 0) {
        fail("not a Stata .dta file: the file is empty");
    }
    if (not dtaOldRelease($data[0])) {
        fail("not a Stata .dta file of a known format");
    }
    def old as DtaHead init dtaOldHead($data, $opts);
    return dtaBuild($data, $old, DtaTail{strls: {}, labels: dtaOldLabels($data, $old)});
}

/**
 * The character set of a file's text.
 *
 * @param opts {Options} the options
 * @param release {int} the format
 * @return {string} `Options.encoding`, else `utf-8` from 118 on, else `windows-1252`
 */
func dtaCharset(opts as Options, release as int) {
    if ($opts.encoding != "") {
        return charsetName($opts.encoding);
    }
    if ($release >= 118) {
        return "utf-8";
    }
    return "windows-1252";
}

/**
 * Decode text, turning a byte the character set lacks into a statfiles error.
 *
 * @param b {bytes} the text
 * @param charset {string} the character set
 * @return {string} the text without trailing blanks and NULs
 */
func dtaText(b as bytes, charset as string) {
    return dtaDecode($b, $charset, true);
}

/**
 * Decode text, turning a byte the character set lacks into a statfiles
 * error.
 *
 * @param b {bytes} the text
 * @param charset {string} the character set
 * @param trim {bool} whether to drop trailing blanks and NULs
 * @return {string} the text
 */
func dtaDecode(b as bytes, charset as string, trim as bool) {
    def s as string;
    try {
        if ($trim) {
            $s = decodeText($b, $charset);
        } else {
            $s = decodeBytes($b, $charset);
        }
    } catch (e) {
        if ($e.kind == ERROR_KIND) {
            throw $e;
        }
        fail("text that is not valid " + $charset +
            " (set Options.encoding if the file is in another character set)");
    }
    return $s;
}

/**
 * A zero-terminated text field.
 *
 * @param data {bytes} the file
 * @param at {int} the field's offset
 * @param width {int} its width
 * @param charset {string} the character set
 * @return {string} the text before the first NUL
 */
func dtaField(data as bytes, at as int, width as int, charset as string) {
    def end as int init binary.indexOf($data, binary.make(1), $at, $at + $width);
    if ($end < 0) {
        $end = $at + $width;
    }
    return dtaText(binary.slice($data, $at, $end), $charset);
}

/**
 * `count` zero-terminated fields of `width` bytes each.
 *
 * @param data {bytes} the file
 * @param at {int} the first field's offset
 * @param count {int} how many
 * @param width {int} the width of each
 * @param charset {string} the character set
 * @param what {string} what they are, for the message
 * @return {list of string} the texts
 */
func dtaFields(
    data as bytes,
    at as int,
    count as int,
    width as int,
    charset as string,
    what as string) {
    need($data, $at, $count * $width, $what);
    def out as list of string init [];
    for (def i in 0..$count) {
        $out[] = dtaField($data, $at + $i * $width, $width, $charset);
    }
    return $out;
}

/**
 * An unsigned integer of 1 to 8 bytes.
 *
 * @param order {string} `le` or `be`
 * @param data {bytes} the file
 * @param at {int} its offset
 * @param size {int} its size
 * @param what {string} what it is, for the message
 * @return {int} the value
 */
func dtaUint(order as string, data as bytes, at as int, size as int, what as string) {
    need($data, $at, $size, $what);
    if ($size == 1 or $size == 2 or $size == 4) {
        return binary.readUint($order, $data, $at, $size);
    }
    def top as int init $data[$at + $size - 1];
    if ($order == "be") {
        $top = $data[$at];
    }
    if ($size == 8 and $top > 127) {
        fail(io.sprintf("%s at offset %d is too large", $what, $at));
    }
    def v as int init 0;
    for (def i in 0..$size) {
        def k as int init $at + $i;
        if ($order == "le") {
            $k = $at + $size - 1 - $i;
        }
        $v = $v * 256 + $data[$k];
    }
    return $v;
}

/**
 * Check that a tag stands at an offset.
 *
 * @param data {bytes} the file
 * @param at {int} the offset
 * @param tag {string} the tag, such as `<data>`
 * @return {int} the offset after it
 */
func dtaTag(data as bytes, at as int, tag as string) {
    def t as bytes init convert.bytesFromString("utf-8", $tag);
    need($data, $at, len($t), $tag);
    if (binary.indexOf($data, $t, $at, $at + len($t)) != $at) {
        fail(io.sprintf("no %s at offset %d", $tag, $at));
    }
    return $at + len($t);
}

/**
 * Whether a tag stands at an offset.
 *
 * @param data {bytes} the file
 * @param at {int} the offset
 * @param tag {string} the tag
 * @return {bool} true when it does
 */
func dtaIsTag(data as bytes, at as int, tag as string) {
    def t as bytes init convert.bytesFromString("utf-8", $tag);
    return $at + len($t) <= len($data) and binary.indexOf($data, $t, $at, $at + len($t)) == $at;
}

/**
 * A type code in the numbering of format 117.
 *
 * @param raw {int} the code as stored
 * @param release {int} the format
 * @return {int} 1 to 2045 for strN, else one of the `DTA_` type codes
 */
func dtaType(raw as int, release as int) {
    if ($release >= 117) {
        if (($raw >= 1 and $raw <= 2045) or $raw == DTA_STRL or
            ($raw >= DTA_DOUBLE and $raw <= DTA_BYTE)) {
            return $raw;
        }
    } elseif ($release >= 111) {
        if ($raw >= 1 and $raw <= 244) {
            return $raw;
        }
        if ($raw >= 251) {
            return DTA_BYTE - ($raw - 251);
        }
    } else {
        if ($raw >= 128) {
            return $raw - 127;
        }
        def codes as list of int init [98, 105, 108, 102, 100];
        def at as int init lists.indexOf($codes, $raw);
        if ($at >= 0) {
            return DTA_BYTE - $at;
        }
    }
    fail(io.sprintf("unknown variable type %d", $raw));
    return 0;
}

/**
 * The bytes a value of a type takes in a record.
 *
 * @param t {int} the type code
 * @return {int} the width
 */
func dtaWidth(t as int) {
    if ($t <= 2045) {
        return $t;
    }
    if ($t == DTA_STRL or $t == DTA_DOUBLE) {
        return 8;
    }
    if ($t == DTA_FLOAT or $t == DTA_LONG) {
        return 4;
    }
    if ($t == DTA_INT) {
        return 2;
    }
    return 1;
}

/**
 * Stata's name of a type.
 *
 * @param t {int} the type code
 * @return {string} `byte`, `int`, `long`, `float`, `double`, `str<n>` or `strL`
 */
func dtaStorage(t as int) {
    if ($t <= 2045) {
        return "str" + convert.toString($t);
    }
    if ($t == DTA_STRL) {
        return "strL";
    }
    return ["double", "float", "long", "int", "byte"][$t - DTA_DOUBLE];
}

/**
 * Refuse a table of rows that does not fit in the file.
 *
 * @param data {bytes} the file
 * @param at {int} the first record
 * @param rows {int} the records
 * @param record {int} the bytes of one
 */
func dtaNeedRecords(data as bytes, at as int, rows as int, record as int) {
    if ($record == 0) {
        if ($rows > 0) {
            fail("observations without variables");
        }
        return;
    }
    if ($at > len($data) or $rows > (len($data) - $at) // $record) {
        fail(io.sprintf(
            "the file ends inside the data (%d records of %d bytes from offset %d)",
            $rows,
            $record,
            $at));
    }
}

/**
 * The record width of a head's variables.
 *
 * @param head {DtaHead} the head
 * @return {int} the bytes of one record
 */
func dtaRecord(head as DtaHead) {
    def w as int init 0;
    for (def t in $head.types) {
        $w = $w + dtaWidth($t);
    }
    return $w;
}

/**
 * Read the header and descriptors of a format 104 to 115 file.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {DtaHead} the head, `dataAt` set after the expansion fields
 */
func dtaOldHead(data as bytes, opts as Options) {
    need($data, 0, 10, "the header");
    def release as int init $data[0];
    def order as string init "be";
    if ($data[1] == 2) {
        $order = "le";
    } elseif ($data[1] != 1) {
        fail(io.sprintf("unknown byte order %d", $data[1]));
    }
    if ($data[2] != 1) {
        fail(io.sprintf("file type %d is not a dataset", $data[2]));
    }
    def k as int init binary.readUint($order, $data, 4, 2);
    def n as int init binary.readUint($order, $data, 6, 4);
    checkSize($opts, $n, $k);
    def cs as string init dtaCharset($opts, $release);
    def labelWidth as int init 81;
    if ($release < 108) {
        $labelWidth = 32;
    }
    need($data, 10, $labelWidth, "the dataset label");
    def label as string init dtaField($data, 10, $labelWidth, $cs);
    def at as int init 10 + $labelWidth;
    if ($release >= 105) {
        $at = $at + 18;
    }
    def nameWidth as int init 33;
    if ($release < 110) {
        $nameWidth = 9;
    }
    def fmtWidth as int init 49;
    if ($release < 105) {
        $fmtWidth = 7;
    } elseif ($release < 114) {
        $fmtWidth = 12;
    }
    need($data, $at, $k, "the variable types");
    def types as list of int init [];
    for (def i in 0..$k) {
        $types[] = dtaType($data[$at + $i], $release);
    }
    $at = $at + $k;
    def names as list of string init dtaFields(
        $data,
        $at,
        $k,
        $nameWidth,
        $cs,
        "the variable names");
    $at = $at + $k * $nameWidth;
    need($data, $at, 2 * ($k + 1), "the sort list");
    $at = $at + 2 * ($k + 1);
    def formats as list of string init dtaFields($data, $at, $k, $fmtWidth, $cs, "the formats");
    $at = $at + $k * $fmtWidth;
    def labelNames as list of string init dtaFields(
        $data,
        $at,
        $k,
        $nameWidth,
        $cs,
        "the value label names");
    $at = $at + $k * $nameWidth;
    def varLabels as list of string init dtaFields(
        $data,
        $at,
        $k,
        $labelWidth,
        $cs,
        "the variable labels");
    $at = $at + $k * $labelWidth;
    if ($release >= 105) {
        def lenSize as int init 4;
        if ($release < 110) {
            $lenSize = 2;
        }
        while (true) {
            need($data, $at, 1 + $lenSize, "the expansion fields");
            def kind as int init $data[$at];
            def size as int init binary.readUint($order, $data, $at + 1, $lenSize);
            $at = $at + 1 + $lenSize;
            if ($kind == 0 and $size == 0) {
                break;
            }
            need($data, $at, $size, "an expansion field");
            $at = $at + $size;
        }
    }
    def head as DtaHead init DtaHead{
        release: $release,
        order: $order,
        charset: $cs,
        rows: $n,
        label: $label,
        types: $types,
        names: $names,
        formats: $formats,
        labelNames: $labelNames,
        varLabels: $varLabels,
        dataAt: $at,
        after: 0,
        offsets: []
    };
    def record as int init dtaRecord($head);
    dtaNeedRecords($data, $at, $n, $record);
    $head.after = $at + $n * $record;
    return $head;
}

/**
 * Read the value labels after the data of a format 104 to 115 file.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @return {map of string to map of string to string} the tables by name
 */
func dtaOldLabels(data as bytes, head as DtaHead) {
    def out as map of string to map of string to string init {};
    def at as int init $head.after;
    def cs as string init $head.charset;
    while ($at < len($data)) {
        if ($head.release < 108) {
            need($data, $at, 12, "a value label header");
            def n as int init binary.readUint($head.order, $data, $at, 2);
            def name as string init dtaField($data, $at + 2, 9, $cs);
            $at = $at + 12;
            $out[$name] = dtaOldTable($data, $head, $at, $n);
            $at = $at + 10 * $n;
        } else {
            def nameWidth as int init 33;
            if ($head.release < 110) {
                $nameWidth = 9;
            }
            need($data, $at, 4 + $nameWidth + 3, "a value label header");
            def size as int init binary.readUint($head.order, $data, $at, 4);
            def name as string init dtaField($data, $at + 4, $nameWidth, $cs);
            $at = $at + 4 + $nameWidth + 3;
            $out[$name] = dtaLabelTable($data, $head, $at, $size);
            $at = $at + $size;
        }
    }
    return $out;
}

/**
 * Read one value label table of formats 104 and 105: `n` 2-byte values,
 * then `n` 8-byte labels.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the first value's offset
 * @param n {int} the entries
 * @return {map of string to string} the labels by value key
 */
func dtaOldTable(data as bytes, head as DtaHead, at as int, n as int) {
    need($data, $at, 10 * $n, "a value label table");
    def table as map of string to string init {};
    if ($n == 0) {
        return $table;
    }
    def vals as list of int init binary.readInts($head.order, $data, $at, $n, 2);
    for (def i in 0..$n) {
        $table[valueKey(convert.toFloat($vals[$i]))] = dtaField(
            $data,
            $at + 2 * $n + 8 * $i,
            8,
            $head.charset);
    }
    return $table;
}

/**
 * Read one value label table (formats 108 and later).
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the table's offset
 * @param size {int} its declared length
 * @return {map of string to string} the labels by value key
 */
func dtaLabelTable(data as bytes, head as DtaHead, at as int, size as int) {
    need($data, $at, $size, "a value label table");
    if ($size < 8) {
        fail(io.sprintf("a value label table of %d bytes", $size));
    }
    def n as int init binary.readUint($head.order, $data, $at, 4);
    def txtLen as int init binary.readUint($head.order, $data, $at + 4, 4);
    if ($n > ($size - 8) // 8 or 8 + 8 * $n + $txtLen != $size) {
        fail(io.sprintf("a value label table at offset %d whose sizes disagree", $at));
    }
    def table as map of string to string init {};
    if ($n == 0) {
        return $table;
    }
    def offs as list of int init binary.readInts($head.order, $data, $at + 8, $n, 4);
    def vals as list of int init binary.readInts($head.order, $data, $at + 8 + 4 * $n, $n, 4);
    def txt as int init $at + 8 + 8 * $n;
    for (def i in 0..$n) {
        def o as int init $offs[$i];
        if ($o < 0 or $o >= $txtLen) {
            fail(io.sprintf("a value label text offset %d outside its table", $o));
        }
        $table[dtaLabelKey($vals[$i], $head.release)] = dtaField(
            $data,
            $txt + $o,
            $txtLen - $o,
            $head.charset);
    }
    return $table;
}

/**
 * The key of a labelled value: `valueKey` of the value, or the missing code
 * of an extended missing value (formats 113 and later).
 *
 * @param v {int} the value as stored
 * @param release {int} the format
 * @return {string} the key
 */
func dtaLabelKey(v as int, release as int) {
    if ($release >= 113 and $v > 2147483620) {
        return dtaCode($v - 2147483621);
    }
    return valueKey(convert.toFloat($v));
}

/**
 * The missing code of an extended missing value number.
 *
 * @param k {int} 0 for `.`, 1 to 26 for `.a` to `.z`
 * @return {string} the code
 */
func dtaCode(k as int) {
    if ($k == 0) {
        return MISSING_SYSTEM;
    }
    return "." + DTA_LETTERS[$k - 1..$k];
}

/**
 * Read the header and descriptors of a format 117 to 119 file.
 *
 * @param data {bytes} the file
 * @param opts {Options} the options
 * @return {DtaHead} the head, `dataAt` at the first record
 */
func dtaTaggedHead(data as bytes, opts as Options) {
    def at as int init dtaTag($data, 0, DTA_TAGGED);
    def release as int init dtaTaggedRelease($data, $at);
    # the field sizes: K, N, label length, name, format, variable label, sort entry
    def sz as list of int init [2, 8, 2, 129, 57, 321, 2];
    if ($release == 117) {
        $sz = [2, 4, 1, 33, 49, 81, 2];
    } elseif ($release == 119) {
        $sz = [4, 8, 2, 129, 57, 321, 4];
    }
    def nameWidth as int init $sz[3];
    $at = dtaTag($data, $at + 3, "</release><byteorder>");
    def order as string init "le";
    if (dtaIsTag($data, $at, "MSF")) {
        $order = "be";
    } elseif (not dtaIsTag($data, $at, "LSF")) {
        fail("unknown byte order");
    }
    $at = dtaTag($data, $at + 3, "</byteorder><K>");
    def k as int init dtaUint($order, $data, $at, $sz[0], "the variable count");
    $at = dtaTag($data, $at + $sz[0], "</K><N>");
    def n as int init dtaUint($order, $data, $at, $sz[1], "the observation count");
    $at = dtaTag($data, $at + $sz[1], "</N><label>");
    checkSize($opts, $n, $k);
    def cs as string init dtaCharset($opts, $release);
    def labelLen as int init dtaUint($order, $data, $at, $sz[2], "the dataset label");
    $at = $at + $sz[2];
    need($data, $at, $labelLen, "the dataset label");
    def label as string init dtaField($data, $at, $labelLen, $cs);
    $at = dtaTag($data, $at + $labelLen, "</label><timestamp>");
    def stampLen as int init dtaUint($order, $data, $at, 1, "the timestamp");
    $at = dtaTag($data, $at + 1 + $stampLen, "</timestamp></header><map>");
    def offsets as list of int init dtaMap($data, $order, $at);
    $at = dtaTag($data, $at + 14 * 8, "</map><variable_types>");
    need($data, $at, 2 * $k, "the variable types");
    def types as list of int init [];
    if ($k > 0) {
        for (def raw in binary.readInts($order, $data, $at, $k, 2)) {
            $types[] = dtaType($raw & 65535, $release);
        }
    }
    $at = dtaTag($data, $at + 2 * $k, "</variable_types><varnames>");
    def names as list of string init dtaFields(
        $data,
        $at,
        $k,
        $nameWidth,
        $cs,
        "the variable names");
    $at = dtaTag($data, $at + $k * $nameWidth, "</varnames><sortlist>");
    need($data, $at, $sz[6] * ($k + 1), "the sort list");
    $at = dtaTag($data, $at + $sz[6] * ($k + 1), "</sortlist><formats>");
    def formats as list of string init dtaFields($data, $at, $k, $sz[4], $cs, "the formats");
    $at = dtaTag($data, $at + $k * $sz[4], "</formats><value_label_names>");
    def labelNames as list of string init dtaFields(
        $data,
        $at,
        $k,
        $nameWidth,
        $cs,
        "the value label names");
    $at = dtaTag($data, $at + $k * $nameWidth, "</value_label_names><variable_labels>");
    def varLabels as list of string init dtaFields(
        $data,
        $at,
        $k,
        $sz[5],
        $cs,
        "the variable labels");
    $at = dtaTag($data, $at + $k * $sz[5], "</variable_labels>");
    dtaAt($at, $offsets[8], "<characteristics>");
    $at = dtaCharacteristics($data, $order, $at);
    dtaAt($at, $offsets[9], "<data>");
    $at = dtaTag($data, $at, "<data>");
    def head as DtaHead init DtaHead{
        release: $release,
        order: $order,
        charset: $cs,
        rows: $n,
        label: $label,
        types: $types,
        names: $names,
        formats: $formats,
        labelNames: $labelNames,
        varLabels: $varLabels,
        dataAt: $at,
        after: 0,
        offsets: $offsets
    };
    def record as int init dtaRecord($head);
    dtaNeedRecords($data, $at, $n, $record);
    $head.after = $at + $n * $record;
    dtaAt(len($data), $offsets[13], "the end of the file");
    return $head;
}

/**
 * The release of a tagged file.
 *
 * @param data {bytes} the file
 * @param at {int} the offset after `<release>`
 * @return {int} 117, 118 or 119
 */
func dtaTaggedRelease(data as bytes, at as int) {
    for (def r in [117, 118, 119]) {
        if (dtaIsTag($data, $at, convert.toString($r))) {
            return $r;
        }
    }
    fail("unknown .dta release (117, 118 or 119 expected)");
    return 0;
}

/**
 * The 14 offsets of a tagged file's map.
 *
 * @param data {bytes} the file
 * @param order {string} `le` or `be`
 * @param at {int} the first offset's offset
 * @return {list of int} the offsets
 */
func dtaMap(data as bytes, order as string, at as int) {
    need($data, $at, 14 * 8, "the map");
    def offsets as list of int init [];
    for (def i in 0..14) {
        $offsets[] = dtaUint($order, $data, $at + 8 * $i, 8, "a map entry");
    }
    return $offsets;
}

/**
 * Skip the characteristics of a format 117 to 119 file, record by record.
 *
 * @param data {bytes} the file
 * @param order {string} `le` or `be`
 * @param at {int} the offset of `<characteristics>`
 * @return {int} the offset after `</characteristics>`
 */
func dtaCharacteristics(data as bytes, order as string, at as int) {
    $at = dtaTag($data, $at, "<characteristics>");
    while (not dtaIsTag($data, $at, "</characteristics>")) {
        $at = dtaTag($data, $at, "<ch>");
        def size as int init dtaUint($order, $data, $at, 4, "a characteristic");
        need($data, $at + 4, $size, "a characteristic");
        $at = dtaTag($data, $at + 4 + $size, "</ch>");
    }
    return $at + len("</characteristics>");
}

/**
 * Refuse a section that does not start where the map says.
 *
 * @param at {int} where it starts
 * @param mapped {int} where the map puts it
 * @param what {string} the section
 */
func dtaAt(at as int, mapped as int, what as string) {
    if ($at != $mapped) {
        fail(io.sprintf("%s is at offset %d, the map says %d", $what, $at, $mapped));
    }
}

/**
 * Read the strLs and value labels after the data of a format 117 to 119
 * file, up to `</stata_dta>`.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @return {DtaTail} the strLs and value labels
 */
func dtaTaggedTail(data as bytes, head as DtaHead) {
    def strls as map of string to string init {};
    def labels as map of string to map of string to string init {};
    def order as string init $head.order;
    def at as int init dtaTag($data, $head.after, "</data>");
    dtaAt($at, $head.offsets[10], "<strls>");
    $at = dtaTag($data, $at, "<strls>");
    def oSize as int init 8;
    if ($head.release == 117) {
        $oSize = 4;
    }
    while (dtaIsTag($data, $at, "GSO")) {
        def v as int init dtaUint($order, $data, $at + 3, 4, "a strL");
        def o as int init dtaUint($order, $data, $at + 7, $oSize, "a strL");
        $at = $at + 7 + $oSize;
        need($data, $at, 5, "a strL");
        def kind as int init $data[$at];
        def size as int init binary.readUint($order, $data, $at + 1, 4);
        $at = $at + 5;
        need($data, $at, $size, "a strL");
        def body as bytes init binary.slice($data, $at, $at + $size);
        if ($kind == 130) {
            if ($size == 0 or $body[$size - 1] != 0) {
                fail(io.sprintf("a text strL at offset %d without its closing NUL", $at));
            }
            $body = binary.slice($body, 0, $size - 1);
        } elseif ($kind != 129) {
            fail(io.sprintf("a strL of unknown type %d", $kind));
        }
        def key as string init io.sprintf("%d:%d", $v, $o);
        if ($v == 0 and $o == 0 or maps.has($strls, $key)) {
            fail("a strL defined twice or as (0,0): " + $key);
        }
        # a value as stored: blanks kept, and a binary strL's NULs too
        $strls[$key] = dtaDecode($body, $head.charset, false);
        $at = $at + $size;
    }
    $at = dtaTag($data, $at, "</strls>");
    dtaAt($at, $head.offsets[11], "<value_labels>");
    $at = dtaTag($data, $at, "<value_labels>");
    def nameWidth as int init 129;
    if ($head.release == 117) {
        $nameWidth = 33;
    }
    while (dtaIsTag($data, $at, "<lbl>")) {
        $at = $at + 5;
        need($data, $at, 4 + $nameWidth + 3, "a value label header");
        def size as int init binary.readUint($order, $data, $at, 4);
        def name as string init dtaField($data, $at + 4, $nameWidth, $head.charset);
        $at = $at + 4 + $nameWidth + 3;
        $labels[$name] = dtaLabelTable($data, $head, $at, $size);
        $at = dtaTag($data, $at + $size, "</lbl>");
    }
    $at = dtaTag($data, $at, "</value_labels>");
    dtaAt($at, $head.offsets[12], "</stata_dta>");
    $at = dtaTag($data, $at, "</stata_dta>");
    if ($at != len($data)) {
        fail(io.sprintf("%d bytes after </stata_dta>", len($data) - $at));
    }
    return DtaTail{strls: $strls, labels: $labels};
}

/**
 * `n` empty missing codes.
 *
 * @param n {int} how many
 * @return {list of string} the codes
 */
func dtaBlank(n as int) {
    if ($n == 0) {
        return [];
    }
    return strings.split(strings.repeat(",", $n - 1), ",");
}

/**
 * Build the dataset from a parsed head.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param tail {DtaTail} its strLs and value labels
 * @return {Dataset} the dataset
 */
func dtaBuild(data as bytes, head as DtaHead, tail as DtaTail) {
    def ds as Dataset init Dataset{
        format: "dta",
        version: convert.toString($head.release),
        name: "",
        label: $head.label,
        encoding: $head.charset,
        rowCount: $head.rows,
        variables: [],
        numbers: [],
        texts: [],
        missing: []
    };
    def record as int init dtaRecord($head);
    def offset as int init $head.dataAt;
    for (def i in 0..len($head.types)) {
        def t as int init $head.types[$i];
        def v as Variable init Variable{
            name: $head.names[$i],
            label: $head.varLabels[$i],
            type: "numeric",
            storage: dtaStorage($t),
            width: 0,
            format: $head.formats[$i],
            valueLabels: {},
            missingValues: [],
            missingRange: []
        };
        def col as DtaColumn;
        if ($t <= 2045) {
            $v.type = "string";
            $v.width = $t;
            $col = dtaStrings($data, $head, $offset, $record, $t);
        } elseif ($t == DTA_STRL) {
            $v.type = "string";
            $col = dtaStrls($data, $head, $offset, $record, $tail.strls);
        } else {
            $v.width = dtaWidth($t);
            $col = dtaNumbers($data, $head, $offset, $record, $t);
            def ln as string init $head.labelNames[$i];
            if ($ln != "" and maps.has($tail.labels, $ln)) {
                $v.valueLabels = $tail.labels[$ln];
            }
        }
        $ds.variables[] = $v;
        $ds.numbers[] = $col.numbers;
        $ds.texts[] = $col.texts;
        $ds.missing[] = $col.missing;
        $offset = $offset + dtaWidth($t);
    }
    return $ds;
}

/**
 * Read a numeric column in bulk and mark its missing values.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the column's offset in the first record
 * @param record {int} the record width
 * @param t {int} the type code
 * @return {DtaColumn} the values and missing codes
 */
func dtaNumbers(data as bytes, head as DtaHead, at as int, record as int, t as int) {
    def n as int init $head.rows;
    if ($n == 0) {
        return DtaColumn{numbers: [], texts: [], missing: []};
    }
    def nums as list of float init dtaChunk(
        $data,
        $head,
        $at,
        $record,
        $t,
        0,
        math.min(DTA_CHUNK, $n));
    def done as int init math.min(DTA_CHUNK, $n);
    while ($done < $n) {
        def count as int init math.min(DTA_CHUNK, $n - $done);
        $nums = lists.concat($nums, dtaChunk($data, $head, $at, $record, $t, $done, $count));
        $done = $done + $count;
    }
    def top as float init dtaTop($t, $head.release);
    def oldDot as bool init $head.release <= 105 and $t == DTA_DOUBLE and
        lists.contains($nums, DTA_OLD_DOUBLE_DOT);
    if (stats.max($nums) <= $top and not $oldDot) {
        return DtaColumn{numbers: $nums, texts: [], missing: dtaBlank($n)};
    }
    def miss as list of string init [];
    for (def r in 0..$n) {
        def x as float init $nums[$r];
        if ($x > $top) {
            $miss[] = dtaMissing($x, $t, $head.release);
            $nums[$r] = 0.0;
        } elseif ($oldDot and $x == DTA_OLD_DOUBLE_DOT) {
            $miss[] = MISSING_SYSTEM;
            $nums[$r] = 0.0;
        } else {
            $miss[] = "";
        }
    }
    return DtaColumn{numbers: $nums, texts: [], missing: $miss};
}

/**
 * Read `count` values of a numeric column in one bulk read.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the column's offset in the first record
 * @param record {int} the record width
 * @param t {int} the type code
 * @param from {int} the first row
 * @param count {int} the rows
 * @return {list of float} the values as stored
 */
func dtaChunk(
    data as bytes,
    head as DtaHead,
    at as int,
    record as int,
    t as int,
    from as int,
    count as int) {
    def size as int init dtaWidth($t);
    def start as int init $at + $from * $record;
    if ($t == DTA_FLOAT or $t == DTA_DOUBLE) {
        try {
            return binary.readFloats($head.order, $data, $start, $count, $size, $record);
        } catch (e) {
            fail(io.sprintf(
                "a %s that is not a number (NaN or infinity) near offset %d",
                dtaStorage($t),
                $start));
        }
    }
    return linalg.scale(binary.readInts($head.order, $data, $start, $count, $size, $record), 1.0);
}

/**
 * The largest nonmissing value of a numeric type.
 *
 * @param t {int} the type code
 * @param release {int} the format
 * @return {float} the value; anything above is missing
 */
func dtaTop(t as int, release as int) {
    if ($t == DTA_FLOAT) {
        return DTA_FLOAT_MAX;
    }
    if ($t == DTA_DOUBLE) {
        return DTA_DOUBLE_MAX;
    }
    def tops as list of float init [2147483620.0, 32740.0, 100.0];
    if ($release < 113) {
        $tops = [2147483646.0, 32766.0, 126.0];
    }
    return $tops[$t - DTA_LONG];
}

/**
 * The missing code of a value above its type's largest nonmissing value.
 *
 * @param x {float} the value
 * @param t {int} the type code
 * @param release {int} the format
 * @return {string} `.` or `.a` to `.z`
 */
func dtaMissing(x as float, t as int, release as int) {
    if ($release < 113) {
        return MISSING_SYSTEM;
    }
    def k as int init 0;
    if ($t == DTA_FLOAT) {
        $k = math.floor(($x / DTA_FLOAT_DOT - 1.0) * 4096.0);
    } elseif ($t == DTA_DOUBLE) {
        $k = math.floor(($x / DTA_DOUBLE_DOT - 1.0) * 4096.0);
    } else {
        $k = convert.toInt($x - dtaTop($t, $release) - 1.0);
    }
    if ($k > 26) {
        fail(io.sprintf("a %s missing value above .z", dtaStorage($t)));
    }
    return dtaCode($k);
}

/**
 * Read a fixed-width string column: each value up to its first NUL, its
 * blanks kept.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the column's offset in the first record
 * @param record {int} the record width
 * @param width {int} the string width
 * @return {DtaColumn} the texts
 */
func dtaStrings(data as bytes, head as DtaHead, at as int, record as int, width as int) {
    def out as list of string init [];
    def nul as bytes init binary.make(1);
    def cs as string init $head.charset;
    def utf8 as bool init $cs == "utf-8";
    def o as int init $at;
    try {
        for (def r in 0..$head.rows) {
            def end as int init binary.indexOf($data, $nul, $o, $o + $width);
            if ($end < 0) {
                $end = $o + $width;
            }
            # trailing blanks are data in Stata: only the NUL padding goes
            if ($utf8) {
                $out[] = convert.stringFromBytes("utf-8", binary.slice($data, $o, $end));
            } else {
                $out[] = encoding.decode($cs, binary.slice($data, $o, $end));
            }
            $o = $o + $record;
        }
    } catch (e) {
        fail(io.sprintf(
            "text that is not valid %s near offset %d (set Options.encoding if the file is in another character set)",
            $cs,
            $o));
    }
    return DtaColumn{numbers: [], texts: $out, missing: dtaBlank($head.rows)};
}

/**
 * Read a strL column: each cell a (v,o) reference into the strLs.
 *
 * @param data {bytes} the file
 * @param head {DtaHead} its head
 * @param at {int} the column's offset in the first record
 * @param record {int} the record width
 * @param strls {map of string to string} the strLs by `v:o`
 * @return {DtaColumn} the texts
 */
func dtaStrls(
    data as bytes,
    head as DtaHead,
    at as int,
    record as int,
    strls as map of string to string) {
    def vSize as int init 4;
    if ($head.release == 118) {
        $vSize = 2;
    } elseif ($head.release == 119) {
        $vSize = 3;
    }
    def out as list of string init [];
    def o as int init $at;
    for (def r in 0..$head.rows) {
        def v as int init dtaUint($head.order, $data, $o, $vSize, "a strL reference");
        def obs as int init dtaUint(
            $head.order,
            $data,
            $o + $vSize,
            8 - $vSize,
            "a strL reference");
        if ($v == 0 and $obs == 0) {
            $out[] = "";
        } else {
            def key as string init io.sprintf("%d:%d", $v, $obs);
            if (not maps.has($strls, $key)) {
                fail(io.sprintf(
                    "row %d refers to strL (%d,%d), which the file does not hold",
                    $r,
                    $v,
                    $obs));
            }
            $out[] = $strls[$key];
        }
        $o = $o + $record;
    }
    return DtaColumn{numbers: [], texts: $out, missing: dtaBlank($head.rows)};
}
