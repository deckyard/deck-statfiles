# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - the xpt topic: SAS XPORT .xpt, versions 5 and 8 (SAS TS-140
# and the "Record Layout for a SAS Version 8 or 9 Data Set in SAS Transport
# Format"). Spliced into statfiles.j via include.
#
# A file is a run of 80-byte records: three library header records, then
# per member a member header, a descriptor header, two member records, a
# NAMESTR header, the NAMESTR descriptors streamed in 80-byte pieces, in
# version 8 an optional LABELV8 / LABELV9 section, an OBS header and the
# observations streamed the same way. Every streamed section is padded to
# the record boundary with blanks. Numbers are IBM System/360 hex floats.

# The length of every record.
def const XPT_RECORD as int init 80;

# The character set of the text unless Options.encoding names another.
def const XPT_DEFAULT_CHARSET as string init "windows-1252";

# The fixed text around a header record's name: bytes 0-19 and 28-47.
def const XPT_HEADER_HEAD as string init "HEADER RECORD*******";
def const XPT_HEADER_TAIL as string init "HEADER RECORD!!!!!!!";

# 2^53: a mantissa below it converts to a float exactly.
def const XPT_EXACT as int init 9007199254740992;

# How far a fraction of 54 to 56 bits is shifted right to fit 53 bits,
# indexed by its bits above the 53rd.
def const XPT_SHIFTS as list of int init [0, 1, 2, 2, 3, 3, 3, 3];

# The power of two of a float's lowest table entry, see xptPowers.
def const XPT_POW_LOW as int init -320;

/*
 * One member of a transport file, as its headers describe it; the cells
 * are decoded later by xptDecode.
 */
def struct XptMember {
    name as string,
    label as string,
    variables as list of Variable,
    numeric as list of bool,
    widths as list of int,
    positions as list of int,
    rowLength as int,
    rowCount as int,
    dataStart as int,
    dataEnd as int
};

/*
 * A variable as its NAMESTR record describes it, with the stored length
 * and the position in the row.
 */
def struct XptField {
    variable as Variable,
    width as int,
    position as int
};

/*
 * One entry of a LABELV8 / LABELV9 section: the variable's index and its
 * full name, label and format (`""` name or format: keep the NAMESTR's).
 */
def struct XptLabel {
    index as int,
    name as string,
    label as string,
    format as string
};

/* One decoded numeric column. */
def struct XptColumn {
    numbers as list of float,
    missing as list of string
};

/* A LABELV8 / LABELV9 section: its entries and the offset after it. */
def struct XptLabels {
    entries as list of XptLabel,
    end as int
};

/**
 * Whether the first bytes are those of this format: the library header
 * record of version 5 (`LIBRARY`) or version 8 (`LIBV8`).
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikeXpt(data as bytes) {
    if (len($data) < XPT_RECORD) {
        return false;
    }
    def name as string init xptHeaderName($data, 0);
    return $name == "LIBRARY" or $name == "LIBV8";
}

/**
 * Read a SAS XPORT .xpt file of one member (data set). A file of several
 * members is an error that names them; `readXptMembers` reads them all.
 *
 * Text is decoded from `Options.encoding`, else from windows-1252 (the
 * format records no character set). A missing number has the code `.`,
 * `.a` to `.z` or `._`. The rows are counted from the length of the data:
 * blank rows inside the final record are its padding, unless a version 8
 * file states its row count.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {Dataset} its contents; `name` and `label` are the member's,
 *   `format` is `xpt`, `version` `5` or `8`
 * @throws {Error} kind `"statfiles"` for a malformed file or one that does
 *   not hold exactly one member, `"limit"` over `Options.maxCells`
 * @example
 *   def ds as statfiles.Dataset init statfiles.readXpt(fs.readBytes("dm.xpt"), statfiles.options());
 */
export func readXpt(data as bytes, opts as Options) {
    def charset as string init xptCharset($opts);
    def members as list of XptMember init xptScan($data, $charset);
    if (len($members) == 0) {
        fail("the XPORT file holds no member");
    }
    if (len($members) > 1) {
        def names as list of string init [];
        for (def m in $members) {
            $names[] = $m.name;
        }
        fail(io.sprintf(
            "the XPORT file holds %d members (%s); readXptMembers reads them all",
            len($members),
            strings.join($names, ", ")));
    }
    xptCheckCells($opts, $members[0], 0);
    return xptDecode($data, $members[0], xptVersion($data), $charset, xptPowers());
}

/**
 * Read every member (data set) of a SAS XPORT .xpt file, in file order.
 * `Options.maxCells` caps the cells of all members together.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {list of Dataset} one per member, as `readXpt` describes it
 * @throws {Error} kind `"statfiles"` for a malformed file, `"limit"` over
 *   `Options.maxCells`
 * @example
 *   for (def ds in statfiles.readXptMembers(fs.readBytes("lib.xpt"), statfiles.options())) {
 *       io.printf("%s: %d rows\n", $ds.name, $ds.rowCount);
 *   }
 */
export func readXptMembers(data as bytes, opts as Options) {
    def charset as string init xptCharset($opts);
    def members as list of XptMember init xptScan($data, $charset);
    def used as int init 0;
    for (def m in $members) {
        xptCheckCells($opts, $m, $used);
        $used = $used + $m.rowCount * len($m.variables);
    }
    def version as string init xptVersion($data);
    def powers as list of float init xptPowers();
    def out as list of Dataset init [];
    for (def m in $members) {
        $out[] = xptDecode($data, $m, $version, $charset, $powers);
    }
    return $out;
}

/**
 * The character set to decode text from, and a check of the options.
 *
 * @param opts {Options} the options
 * @return {string} an `encoding` codec name, or `utf-8`
 */
func xptCharset(opts as Options) {
    checkSize($opts, 0, 0);
    if ($opts.encoding == "") {
        return XPT_DEFAULT_CHARSET;
    }
    return charsetName($opts.encoding);
}

/**
 * Throw `"limit"` when a member's cells take the total over the cap.
 *
 * @param opts {Options} the options
 * @param m {XptMember} the member
 * @param used {int} the cells of the members before it
 */
func xptCheckCells(opts as Options, m as XptMember, used as int) {
    def cells as int init $m.rowCount * len($m.variables);
    if ($used + $cells > $opts.maxCells) {
        failLimit(io.sprintf(
            "%d rows of %d variables in member %s take the file over %d cells",
            $m.rowCount,
            len($m.variables),
            $m.name,
            $opts.maxCells));
    }
}

/**
 * The XPORT version of a file whose library header has been checked.
 *
 * @param data {bytes} the file
 * @return {string} `5` or `8`
 */
func xptVersion(data as bytes) {
    if (xptHeaderName($data, 0) == "LIBV8") {
        return "8";
    }
    return "5";
}

/**
 * The bytes `start` to `end` of a record as text, one character per byte.
 *
 * @param data {bytes} the file
 * @param pos {int} the record's offset
 * @param start {int} the first byte, within the record
 * @param end {int} the byte after the last
 * @return {string} the text
 */
func xptAscii(data as bytes, pos as int, start as int, end as int) {
    return encoding.decode("iso-8859-1", binary.slice($data, $pos + $start, $pos + $end));
}

/**
 * The name of a header record (`LIBRARY`, `MEMBV8`, `OBS`, ...).
 *
 * @param data {bytes} the file
 * @param pos {int} the record's offset; the record must be inside the file
 * @return {string} the name without its blanks, `""` when the record is
 *   not a header record
 */
func xptHeaderName(data as bytes, pos as int) {
    if (xptAscii($data, $pos, 0, 20) != XPT_HEADER_HEAD or
        xptAscii($data, $pos, 28, 48) != XPT_HEADER_TAIL) {
        return "";
    }
    return strings.trimRight(xptAscii($data, $pos, 20, 28));
}

/**
 * Throw unless a whole header record of the given name is at `pos`.
 *
 * @param data {bytes} the file
 * @param pos {int} the record's offset
 * @param want {string} the header's name
 */
func xptExpectHeader(data as bytes, pos as int, want as string) {
    need($data, $pos, XPT_RECORD, "the " + $want + " header record");
    if (xptHeaderName($data, $pos) != $want) {
        fail(io.sprintf("expected the %s header record at offset %d", $want, $pos));
    }
}

/**
 * A count written in decimal digits in a header record. Leading zeros and
 * blanks around the digits are allowed (SAS writes `0002`, or `1`
 * followed by blanks), nothing else; all zeros or all blanks is 0.
 *
 * @param data {bytes} the file
 * @param pos {int} the record's offset
 * @param start {int} the first byte of the field
 * @param end {int} the byte after it
 * @param what {string} what the field counts, for the message
 * @return {int} the count
 */
func xptCount(data as bytes, pos as int, start as int, end as int, what as string) {
    def m as regex.Match init regex.find(
        '^ *0*([0-9]{0,9}) *$',
        xptAscii($data, $pos, $start, $end));
    if ($m.start < 0) {
        fail(io.sprintf("the %s at offset %d is not a number", $what, $pos + $start));
    }
    if ($m.groups[0] == "") {
        return 0;
    }
    return convert.toInt($m.groups[0]);
}

/**
 * Whether `count` bytes from `offset` are all blanks.
 *
 * @param data {bytes} the file
 * @param offset {int} the first byte
 * @param count {int} how many bytes
 * @return {bool} true when every byte is 0x20
 */
func xptBlank(data as bytes, offset as int, count as int) {
    for (def i in $offset..$offset + $count) {
        if ($data[$i] != 32) {
            return false;
        }
    }
    return true;
}

/**
 * The offset of the next record boundary at or after `pos`.
 *
 * @param pos {int} an offset
 * @return {int} the boundary
 */
func xptRecordEnd(pos as int) {
    return ($pos + XPT_RECORD - 1) // XPT_RECORD * XPT_RECORD;
}

/**
 * Walk the file's records and describe every member.
 *
 * @param data {bytes} the file
 * @param charset {string} the character set of names and labels
 * @return {list of XptMember} the members, in file order
 */
func xptScan(data as bytes, charset as string) {
    if (not looksLikeXpt($data)) {
        fail("not a SAS XPORT file (no library header record)");
    }
    if (len($data) % XPT_RECORD != 0) {
        fail(io.sprintf(
            "the XPORT file is %d bytes, not a whole number of 80-byte records (truncated?)",
            len($data)));
    }
    def v8 as bool init xptVersion($data) == "8";
    need($data, 0, 3 * XPT_RECORD, "the library header");
    def members as list of XptMember init [];
    def pos as int init 3 * XPT_RECORD;
    while ($pos < len($data)) {
        def m as XptMember init xptMember($data, $pos, $v8, $charset);
        $members[] = $m;
        $pos = $m.dataEnd;
    }
    return $members;
}

/**
 * The offset where a member's data area ends: the next member header
 * record, or the end of the file.
 *
 * @param data {bytes} the file
 * @param from {int} a record boundary inside or at the end of the area
 * @param v8 {bool} whether the file is version 8
 * @return {int} the offset
 */
func xptDataEnd(data as bytes, from as int, v8 as bool) {
    def head as string init XPT_HEADER_HEAD + "MEMBER  " + XPT_HEADER_TAIL;
    if ($v8) {
        $head = XPT_HEADER_HEAD + "MEMBV8  " + XPT_HEADER_TAIL;
    }
    def needle as bytes init encoding.encode("ascii", $head);
    def at as int init $from;
    while (true) {
        $at = binary.indexOf($data, $needle, $at);
        if ($at < 0) {
            return len($data);
        }
        if ($at % XPT_RECORD == 0) {
            return $at;
        }
        $at = $at + 1;
    }
    return len($data);
}

/**
 * Describe the member whose header record is at `pos`.
 *
 * @param data {bytes} the file
 * @param pos {int} the member header record's offset
 * @param v8 {bool} whether the file is version 8
 * @param charset {string} the character set of names and labels
 * @return {XptMember} the member, with its row count
 */
func xptMember(data as bytes, pos as int, v8 as bool, charset as string) {
    def nameWidth as int init 8;
    def kinds as list of string init ["MEMBER", "DSCRPTR", "NAMESTR", "OBS"];
    if ($v8) {
        $nameWidth = 32;
        $kinds = ["MEMBV8", "DSCPTV8", "NAMSTV8", "OBSV8"];
    }
    xptExpectHeader($data, $pos, $kinds[0]);
    def size as int init xptCount($data, $pos, 74, 78, "NAMESTR length");
    if ($size != 140 and $size != 136) {
        fail(io.sprintf("the NAMESTR length is %d, not 140 or 136", $size));
    }
    xptExpectHeader($data, $pos + XPT_RECORD, $kinds[1]);
    $pos = $pos + 2 * XPT_RECORD;
    need($data, $pos, 3 * XPT_RECORD, "the member header");
    def name as string init decodeText(
        binary.slice($data, $pos + 8, $pos + 8 + $nameWidth),
        $charset);
    def label as string init decodeText(
        binary.slice($data, $pos + XPT_RECORD + 32, $pos + XPT_RECORD + 72),
        $charset);
    $pos = $pos + 2 * XPT_RECORD;
    xptExpectHeader($data, $pos, $kinds[2]);
    def count as int init xptCount($data, $pos, 54, 58, "variable count");
    $pos = $pos + XPT_RECORD;
    need($data, $pos, $count * $size, "the NAMESTR records");
    def m as XptMember init XptMember{
        name: $name,
        label: $label,
        variables: [],
        numeric: [],
        widths: [],
        positions: [],
        rowLength: 0,
        rowCount: 0,
        dataStart: 0,
        dataEnd: 0
    };
    for (def i in 0..$count) {
        def f as XptField init xptNamestr($data, $pos + $i * $size, $v8, $charset);
        $m.variables[] = $f.variable;
        $m.numeric[] = $f.variable.type == "numeric";
        $m.widths[] = $f.width;
        $m.positions[] = $f.position;
        $m.rowLength = $m.rowLength + $f.width;
    }
    for (def i in 0..$count) {
        if ($m.positions[$i] + $m.widths[$i] > $m.rowLength) {
            fail(io.sprintf(
                "variable %s lies outside the %d-byte observation",
                $m.variables[$i].name,
                $m.rowLength));
        }
    }
    $pos = xptRecordEnd($pos + $count * $size);
    need($data, $pos, XPT_RECORD, "the OBS header record");
    def next as string init xptHeaderName($data, $pos);
    if ($v8 and ($next == "LABELV8" or $next == "LABELV9")) {
        def section as XptLabels init xptLabels($data, $pos, $next == "LABELV9", $count, $charset);
        for (def e in $section.entries) {
            if ($e.name != "") {
                $m.variables[$e.index].name = $e.name;
            }
            $m.variables[$e.index].label = $e.label;
            if ($e.format != "") {
                $m.variables[$e.index].format = $e.format;
            }
        }
        $pos = $section.end;
        need($data, $pos, XPT_RECORD, "the OBSV8 header record");
    }
    xptExpectHeader($data, $pos, $kinds[3]);
    def declared as int init 0;
    if ($v8) {
        $declared = xptCount($data, $pos, 48, 80, "observation count");
    }
    $m.dataStart = $pos + XPT_RECORD;
    $m.dataEnd = xptDataEnd($data, $m.dataStart, $v8);
    $m.rowCount = xptRows($data, $m, $m.dataEnd, $declared);
    return $m;
}

/**
 * The variable a NAMESTR record describes.
 *
 * @param data {bytes} the file
 * @param at {int} the record's offset
 * @param v8 {bool} whether the file is version 8 (long name at byte 88)
 * @param charset {string} the character set of names and labels
 * @return {XptField} the variable, its stored length and its position
 */
func xptNamestr(data as bytes, at as int, v8 as bool, charset as string) {
    def ntype as int init binary.readUint("be", $data, $at, 2);
    def width as int init binary.readUint("be", $data, $at + 4, 2);
    def name as string init decodeText(binary.slice($data, $at + 8, $at + 16), $charset);
    if ($v8) {
        def long as string init decodeText(binary.slice($data, $at + 88, $at + 120), $charset);
        if ($long != "") {
            $name = $long;
        }
    }
    def numeric as bool init $ntype == 1;
    if ($ntype != 1 and $ntype != 2) {
        fail(io.sprintf("variable %s has type %d, not 1 (numeric) or 2 (character)", $name, $ntype));
    }
    if ($numeric and ($width < 2 or $width > 8)) {
        fail(io.sprintf("numeric variable %s is %d bytes long, not 2 to 8", $name, $width));
    }
    if (not $numeric and $width < 1) {
        fail(io.sprintf("character variable %s has length 0", $name));
    }
    def position as int init binary.readInt("be", $data, $at + 84, 4);
    if ($position < 0) {
        fail(io.sprintf("variable %s has a negative position", $name));
    }
    def v as Variable init Variable{
        name: $name,
        label: decodeText(binary.slice($data, $at + 16, $at + 56), $charset),
        type: "string",
        storage: "string",
        width: $width,
        format: xptFormat(
            decodeText(binary.slice($data, $at + 56, $at + 64), $charset),
            binary.readUint("be", $data, $at + 64, 2),
            binary.readUint("be", $data, $at + 66, 2)),
        valueLabels: {},
        missingValues: [],
        missingRange: []
    };
    if ($numeric) {
        $v.type = "numeric";
        $v.storage = "numeric";
    }
    return XptField{variable: $v, width: $width, position: $position};
}

/**
 * Read a version 8 LABELV8 or LABELV9 section: per variable its number,
 * the lengths of its name and label (LABELV9: also of its format and
 * informat), then the texts, streamed and padded to the record boundary.
 *
 * @param data {bytes} the file
 * @param pos {int} the offset of the section's header record
 * @param v9 {bool} whether it is LABELV9
 * @param count {int} the number of variables
 * @param charset {string} the character set of the texts
 * @return {XptLabels} the entries and the offset after the section
 */
func xptLabels(data as bytes, pos as int, v9 as bool, count as int, charset as string) {
    def what as string init "the LABELV8 records";
    def head as int init 6;
    if ($v9) {
        $what = "the LABELV9 records";
        $head = 10;
    }
    def labelled as int init xptCount($data, $pos, 48, 80, "label count");
    def at as int init $pos + XPT_RECORD;
    def entries as list of XptLabel init [];
    for (def i in 0..$labelled) {
        need($data, $at, $head, $what);
        def num as int init binary.readUint("be", $data, $at, 2);
        if ($num < 1 or $num > $count) {
            fail(io.sprintf("%s name variable %d of %d", $what, $num, $count));
        }
        def lengths as list of int init [
            binary.readUint("be", $data, $at + 2, 2),
            binary.readUint("be", $data, $at + 4, 2),
            0,
            0
        ];
        if ($v9) {
            $lengths[2] = binary.readUint("be", $data, $at + 6, 2);
            $lengths[3] = binary.readUint("be", $data, $at + 8, 2);
        }
        $at = $at + $head;
        need($data, $at, $lengths[0] + $lengths[1] + $lengths[2] + $lengths[3], $what);
        def texts as list of string init [];
        for (def n in $lengths) {
            $texts[] = decodeText(binary.slice($data, $at, $at + $n), $charset);
            $at = $at + $n;
        }
        $entries[] = XptLabel{
            index: $num - 1,
            name: $texts[0],
            label: $texts[1],
            format: $texts[2]
        };
    }
    return XptLabels{entries: $entries, end: xptRecordEnd($at)};
}

/**
 * A display format as SAS writes it: the name, the width and a period,
 * then the decimals (`DATE9.`, `8.2`, `$CHAR20.`).
 *
 * @param name {string} the format's name, `""` for the default
 * @param width {int} its width, 0 if none
 * @param decimals {int} its decimals, 0 if none
 * @return {string} the format, `""` when the variable has none
 */
func xptFormat(name as string, width as int, decimals as int) {
    if ($name == "" and $width == 0 and $decimals == 0) {
        return "";
    }
    def out as string init $name;
    if ($width > 0) {
        $out = $out + convert.toString($width);
    }
    $out = $out + ".";
    if ($decimals > 0) {
        $out = $out + convert.toString($decimals);
    }
    return $out;
}

/**
 * The number of rows in a member's data area.
 *
 * The data is padded with blanks to a record boundary, so fewer than 80
 * bytes of padding follow the last row. A version 8 file may state its
 * row count in the OBSV8 header record (SAS 9 and ReadStat do); the area
 * must then hold exactly that many rows and their padding. Otherwise the
 * count is the most rows that fit, less the all-blank rows that lie
 * wholly inside the last record (they are padding): a real final row that
 * is all blanks is ambiguous and is read as padding, as ReadStat does.
 *
 * @param data {bytes} the file
 * @param m {XptMember} the member, with its rowLength and dataStart
 * @param end {int} the offset where the data area ends
 * @param declared {int} the row count the OBSV8 header states, 0 if none
 * @return {int} the rows
 */
func xptRows(data as bytes, m as XptMember, end as int, declared as int) {
    def size as int init $end - $m.dataStart;
    def rowLength as int init $m.rowLength;
    if ($rowLength == 0) {
        if (not xptBlank($data, $m.dataStart, $size)) {
            fail("member " + $m.name + " has no variables but holds data");
        }
        return 0;
    }
    if ($declared > 0) {
        def used as int init $declared * $rowLength;
        if ($used > $size or $size - $used >= XPT_RECORD) {
            fail(io.sprintf(
                "member %s declares %d rows of %d bytes, its data area is %d bytes",
                $m.name,
                $declared,
                $rowLength,
                $size));
        }
        if (not xptBlank($data, $m.dataStart + $used, $size - $used)) {
            fail("the padding after the data of member " + $m.name + " is not blank");
        }
        return $declared;
    }
    if ($size == 0) {
        return 0;
    }
    def most as int init $size // $rowLength;
    def least as int init ($size - XPT_RECORD) // $rowLength + 1;
    if ($most < $least) {
        fail(io.sprintf(
            "the data area of member %s (%d bytes) ends inside a %d-byte row",
            $m.name,
            $size,
            $rowLength));
    }
    def used as int init $most * $rowLength;
    if (not xptBlank($data, $m.dataStart + $used, $size - $used)) {
        fail("the padding after the data of member " + $m.name + " is not blank");
    }
    def rows as int init $most;
    while ($rows > $least and xptBlank($data, $m.dataStart + ($rows - 1) * $rowLength, $rowLength)) {
        $rows = $rows - 1;
    }
    return $rows;
}

/**
 * The powers of two a converted number is scaled by: entry `i` is
 * 2^(i + XPT_POW_LOW), from 2^-320 to 2^199, each exact.
 *
 * @return {list of float} the powers
 */
func xptPowers() {
    def low as float init 1.0;
    for (def i in 0..-XPT_POW_LOW) {
        $low = $low / 2.0;
    }
    def out as list of float init [];
    def p as float init $low;
    for (def i in 0..520) {
        $out[] = $p;
        $p = $p * 2.0;
    }
    return $out;
}

/**
 * The missing code of a number's first byte when the rest is zero:
 * `.` for 0x2e, `._` for 0x5f, `.a` to `.z` for `A` to `Z`.
 *
 * @return {list of string} 256 entries, `""` for a byte that is no code
 */
func xptMissingCodes() {
    def out as list of string init [];
    for (def b in 0..256) {
        if ($b == 0x2e) {
            $out[] = MISSING_SYSTEM;
        } elseif ($b == 0x5f) {
            $out[] = "._";
        } elseif ($b >= 0x41 and $b <= 0x5a) {
            $out[] = "." + convert.fromCodepoint($b + 32);
        } else {
            $out[] = "";
        }
    }
    return $out;
}

/**
 * Decode a member's cells into a Dataset, one column at a time.
 *
 * @param data {bytes} the file
 * @param m {XptMember} the member
 * @param version {string} `5` or `8`
 * @param charset {string} the character set of the text
 * @param powers {list of float} from xptPowers
 * @return {Dataset} the member's contents
 */
func xptDecode(
    data as bytes,
    m as XptMember,
    version as string,
    charset as string,
    powers as list of float) {
    def codes as list of string init xptMissingCodes();
    def numbers as list of list of float init [];
    def texts as list of list of string init [];
    def missing as list of list of string init [];
    def present as list of string init [];
    for (def r in 0..$m.rowCount) {
        $present[] = "";
    }
    for (def i in 0..len($m.variables)) {
        def start as int init $m.dataStart + $m.positions[$i];
        if ($m.numeric[$i]) {
            def col as XptColumn init xptNumbers(
                xptRawColumn($data, $start, $m.rowCount, $m.widths[$i], $m.rowLength),
                $codes,
                $powers);
            $numbers[] = $col.numbers;
            $texts[] = [];
            $missing[] = $col.missing;
        } else {
            $numbers[] = [];
            $texts[] = xptTexts($data, $start, $m.rowCount, $m.widths[$i], $m.rowLength, $charset);
            $missing[] = $present;
        }
    }
    return Dataset{
        format: "xpt",
        version: $version,
        name: $m.name,
        label: $m.label,
        encoding: $charset,
        rowCount: $m.rowCount,
        variables: $m.variables,
        numbers: $numbers,
        texts: $texts,
        missing: $missing
    };
}

/**
 * The values of one string column, without trailing blanks.
 *
 * @param data {bytes} the file
 * @param start {int} the offset of the first row's value
 * @param rows {int} the number of rows
 * @param width {int} the stored length
 * @param stride {int} the length of a row
 * @param charset {string} the character set of the text
 * @return {list of string} one value per row
 */
func xptTexts(
    data as bytes,
    start as int,
    rows as int,
    width as int,
    stride as int,
    charset as string) {
    def out as list of string init [];
    def at as int init $start;
    for (def r in 0..$rows) {
        $out[] = decodeText(binary.slice($data, $at, $at + $width), $charset);
        $at = $at + $stride;
    }
    return $out;
}

/**
 * Convert one column of IBM floats.
 *
 * @param raws {list of int} the values from xptRawColumn
 * @param codes {list of string} from xptMissingCodes
 * @param powers {list of float} from xptPowers
 * @return {XptColumn} the numbers (0.0 where missing) and missing codes
 */
func xptNumbers(raws as list of int, codes as list of string, powers as list of float) {
    def nums as list of float init [];
    def miss as list of string init [];
    for (def raw in $raws) {
        def fraction as int init $raw & 0x00FFFFFFFFFFFFFF;
        def first as int init ($raw >> 56) & 0xff;
        if ($fraction == 0) {
            $nums[] = 0.0;
            $miss[] = $codes[$first];
            continue;
        }
        def shift as int init 0;
        if ($fraction >= XPT_EXACT) {
            $shift = XPT_SHIFTS[$fraction >> 53];
            $fraction = $fraction >> $shift;
        }
        def x as float init convert.toFloat($fraction) *
            $powers[4 * ($first & 0x7f) - 312 + $shift - XPT_POW_LOW];
        if ($raw < 0) {
            $x = -$x;
        }
        $nums[] = $x;
        $miss[] = "";
    }
    return XptColumn{numbers: $nums, missing: $miss};
}

/**
 * The numbers of one numeric column as 64-bit IBM floats: the stored bytes
 * at the top, a value shorter than 8 bytes padded with zero bytes on the
 * right. The bytes are read in at most three bulk reads of 4, 2 and 1
 * bytes per value.
 *
 * A number is an IBM hex float: a sign bit, a 7-bit exponent of 16 biased
 * by 64, and a 56-bit fraction; its value is fraction * 16^(exp-64) / 2^56.
 * xptDecode builds it from the integer fraction and a power of two, exact
 * when the fraction has at most 53 significant bits (every value written
 * from an IEEE double); a longer one loses its lowest bits (truncated, as
 * SAS's own converter does).
 *
 * @param data {bytes} the file
 * @param start {int} the offset of the first row's value
 * @param rows {int} the number of rows
 * @param width {int} the stored length, 2 to 8
 * @param stride {int} the length of a row
 * @return {list of int} one value per row
 */
func xptRawColumn(data as bytes, start as int, rows as int, width as int, stride as int) {
    if ($rows == 0) {
        return [];
    }
    if ($width == 8) {
        return binary.readInts("be", $data, $start, $rows, 8, $stride);
    }
    def out as list of int init [];
    def offset as int init 0;
    for (def size in [4, 2, 1]) {
        if ($width - $offset < $size) {
            continue;
        }
        def part as list of int init binary.readInts(
            "be",
            $data,
            $start + $offset,
            $rows,
            $size,
            $stride);
        def mask as int init (1 << (8 * $size)) - 1;
        def shift as int init 8 * (8 - $offset - $size);
        if ($offset == 0) {
            for (def v in $part) {
                $out[] = ($v & $mask) << $shift;
            }
        } else {
            for (def r in 0..$rows) {
                $out[$r] = $out[$r] | (($part[$r] & $mask) << $shift);
            }
        }
        $offset = $offset + $size;
    }
    return $out;
}
