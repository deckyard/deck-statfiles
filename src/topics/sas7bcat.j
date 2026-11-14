# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - the sas7bcat topic: the value labels of SAS format catalogs
# (.sas7bcat), as ReadStat reads them, and attaching them to a data set.
# Spliced into statfiles.j via include; shares the header reader of the
# sas7bdat topic.
#
# A catalog has the header and pages of a data set. Its second page, and
# any later page that starts with `XLSR`, holds an index of XLSR records;
# a record marked `O` points (page, offset) at the start of a format's
# block. A block is a chain of links (next page, next offset, length) whose
# payloads joined make the block: a head with the format's name and its
# entry counts, then one value entry per entry, then the labels.

# The second page holds the first index records.
def const SAS7C_INDEX_PAGE as int init 1;

# Index records are also looked for from this page on.
def const SAS7C_FIRST_SCAN_PAGE as int init 3;

/* One format of a catalog: its name and its value labels. */
def struct Sas7cFormat {
    name as string,
    labels as map of string to string
};

# The sign bit of a 64-bit pattern.
def const SAS7C_SIGN as int init -9223372036854775807 - 1;

/**
 * Read the value labels of a SAS format catalog (`.sas7bcat`).
 *
 * Each format becomes one map from a value, as `valueKey` writes it, to its
 * label: numbers as `3` or `2.5`, special missing values as `.`, `.a` to
 * `.z` or `._`, strings without trailing blanks. A format is keyed by its
 * name in upper case without the period: `WORKSHOP`, `$GENDER` (character
 * formats keep their `$`). Informats are left out, as are entries that
 * cover a range of numbers (`1-5`) and the `OTHER` label; only the start
 * of a character range is read (its layout is not known).
 *
 * The text is decoded from `Options.encoding`, else from the catalog's own
 * character set, else windows-1252. Catalogs written by SAS for UTF-8
 * sessions often declare no character set: set `Options.encoding`.
 *
 * @param data {bytes} the catalog
 * @param opts {Options} how to read it
 * @return {map of string to map of string to string} format name to value
 *   to label
 * @throws {Error} kind `"statfiles"` for a malformed catalog
 * @example
 *   def formats as map of string to map of string to string init statfiles.readSas7bcat(fs.readBytes("formats.sas7bcat"), statfiles.options());
 */
export func readSas7bcat(data as bytes, opts as Options) {
    if (looksLikeSas7bdat($data)) {
        fail("a SAS data set, not a format catalog: readSas7bdat reads it");
    }
    if (not looksLikeSas7bcat($data)) {
        fail("not a SAS format catalog (no sas7bcat signature)");
    }
    def head as Sas7Head init sas7Head($data, $opts);
    if ($head.pageCount <= SAS7C_INDEX_PAGE) {
        fail("the catalog has no index page");
    }
    def size as int init 212 + $head.align;
    def first as int init 856 + 2 * $head.align;
    def flag as int init 50 + $head.align;
    if ($head.u64) {
        $size = $size + 72;
        $first = $first + 144;
        $flag = $flag + 24;
    }
    def pointers as list of int init [];
    def page as int init $head.headerSize + SAS7C_INDEX_PAGE * $head.pageSize;
    def found as list of int init sas7cIndex(
        $data,
        $head,
        $page + $first,
        $page + $head.pageSize,
        $size,
        $flag);
    for (def p in $found) {
        $pointers[] = $p;
    }
    def magic as bytes init encoding.encode("ascii", "XLSR");
    def at as int init 16;
    if ($head.u64) {
        $at = 32;
    }
    for (def i in SAS7C_FIRST_SCAN_PAGE..$head.pageCount) {
        $page = $head.headerSize + $i * $head.pageSize;
        if (binary.slice($data, $page + $at, $page + $at + 4) == $magic) {
            $found = sas7cIndex($data, $head, $page + $at, $page + $head.pageSize, $size, $flag);
            for (def p in $found) {
                $pointers[] = $p;
            }
        }
    }
    def out as map of string to map of string to string init {};
    def last as int init -1;
    for (def p in lists.sort($pointers)) {
        if ($p == $last) {
            continue;
        }
        $last = $p;
        def block as bytes init sas7cBlock($data, $head, $p >> 16, $p & 0xFFFF);
        if (len($block) > 0) {
            def f as Sas7cFormat init sas7cFormat($block, $head);
            if ($f.name != "") {
                $out[$f.name] = $f.labels;
            }
        }
    }
    return $out;
}

/**
 * The block pointers of a run of XLSR index records.
 *
 * @param data {bytes} the catalog
 * @param head {Sas7Head} the header
 * @param from {int} the offset of the first record
 * @param end {int} the end of the page
 * @param size {int} the size of a record
 * @param flag {int} the offset of the `O` mark within a record
 * @return {list of int} each pointer as page * 65536 + offset
 */
func sas7cIndex(
    data as bytes,
    head as Sas7Head,
    from as int,
    end as int,
    size as int,
    flag as int) {
    def magic as bytes init encoding.encode("ascii", "XLSR");
    def out as list of int init [];
    def x as int init $from;
    while ($x + $size <= $end) {
        if (binary.slice($data, $x, $x + 4) != $magic) {
            # some records are preceded by 8 bytes of padding
            $x = $x + 8;
            if ($x + $size > $end or binary.slice($data, $x, $x + 4) != $magic) {
                break;
            }
        }
        if ($data[$x + $flag] == 0x4f) {
            def page as int init 0;
            def pos as int init 0;
            if ($head.u64) {
                $page = binary.readInt($head.order, $data, $x + 8, 8);
                $pos = binary.readUint($head.order, $data, $x + 16, 2);
            } else {
                $page = binary.readUint($head.order, $data, $x + 4, 4);
                $pos = binary.readUint($head.order, $data, $x + 8, 2);
            }
            if ($page < 0 or $page > $head.pageCount) {
                fail(io.sprintf("an index record points at page %d of %d", $page, $head.pageCount));
            }
            $out[] = $page * 65536 + $pos;
        }
        $x = $x + $size;
    }
    return $out;
}

/**
 * Join the links of a block: each link starts with the page and offset of
 * the next one and the length of its own payload.
 *
 * @param data {bytes} the catalog
 * @param head {Sas7Head} the header
 * @param page {int} the first link's page, from 1
 * @param pos {int} its offset in the page
 * @return {bytes} the block
 */
func sas7cBlock(data as bytes, head as Sas7Head, page as int, pos as int) {
    def parts as list of bytes init [];
    def links as int init 0;
    def hl as int init 16;
    if ($head.u64) {
        $hl = 32;
    }
    while ($page > 0 and $pos > 0 and $page <= $head.pageCount and $links < $head.pageCount) {
        $links = $links + 1;
        def at as int init $head.headerSize + ($page - 1) * $head.pageSize + $pos;
        need($data, $at, $hl, "a catalog block");
        def n as int init 0;
        $page = binary.readUint($head.order, $data, $at, 4);
        if ($head.u64) {
            $pos = binary.readUint($head.order, $data, $at + 8, 2);
            $n = binary.readUint($head.order, $data, $at + 10, 2);
        } else {
            $pos = binary.readUint($head.order, $data, $at + 4, 2);
            $n = binary.readUint($head.order, $data, $at + 6, 2);
        }
        need($data, $at + $hl, $n, "a catalog block");
        $parts[] = binary.slice($data, $at + $hl, $at + $hl + $n);
    }
    return binary.join($parts);
}

/**
 * Read one format's block.
 *
 * @param b {bytes} the block
 * @param head {Sas7Head} the header
 * @return {Sas7cFormat} the format; its name is `""` for a block to skip
 *   (an informat, a block too short to hold a format, one of no entries)
 */
func sas7cFormat(b as bytes, head as Sas7Head) {
    def none as Sas7cFormat init Sas7cFormat{name: "", labels: {}};
    def payload as int init 106;
    if (len($b) < $payload) {
        return $none;
    }
    def order as string init $head.order;
    def flags as int init binary.readUint($order, $b, 2, 2);
    def pad as int init 0;
    if (($flags & 0x08) != 0) {
        $pad = 4;
    }
    def capacity as int init 0;
    def used as int init 0;
    def other as int init 0;
    def shift as int init 0;
    if ($head.u64) {
        if (len($b) < 128 + $pad) {
            return $none;
        }
        $capacity = binary.readInt($order, $b, 42 + $pad, 8);
        $used = binary.readInt($order, $b, 50 + $pad, 8);
        $other = binary.readInt($order, $b, 74 + $pad, 8);
        $shift = binary.readInt($order, $b, 124 + $pad, 4);
        $payload = $payload + 32;
    } else {
        if (len($b) < 106 + $pad) {
            return $none;
        }
        $capacity = binary.readInt($order, $b, 38 + $pad, 4);
        $used = binary.readInt($order, $b, 42 + $pad, 4);
        $other = binary.readInt($order, $b, 66 + $pad, 4);
        $shift = binary.readInt($order, $b, 104 + $pad, 2);
    }
    if ($capacity < 0 or $used < 0 or $shift < 0 or $other < 0 or $other > $used) {
        fail(io.sprintf(
            "a format block with %d entries of %d used, OTHER at %d, value shift %d",
            $capacity,
            $used,
            $other,
            $shift));
    }
    def name as string init decodeText(binary.slice($b, 8, 16), $head.charset);
    if ($pad > 0) {
        $pad = $pad + 16;
    }
    if (not $head.u64 and ($flags & 0x80) != 0 or $head.u64 and ($flags & 0x20) != 0) {
        if (len($b) < $payload + $pad + 32) {
            return $none;
        }
        $name = decodeText(binary.slice($b, $payload + $pad, $payload + $pad + 32), $head.charset);
        $pad = $pad + 32;
    }
    if (len($b) < $payload + $pad or $used == 0 or strings.startsWith($name, "@")) {
        return $none;
    }
    return Sas7cFormat{
        name: strings.upper($name),
        labels: sas7cLabels(
            binary.slice($b, $payload + $pad, len($b)),
            $head,
            $capacity,
            $used,
            $other,
            $shift,
            strings.startsWith($name, "$"))
    };
}

/**
 * The value labels of a block: `capacity` value entries, each naming the
 * label it uses, then `used` labels in order. A numeric entry holds the
 * range's start at byte 22 and its end at byte 30, 8-byte big-endian
 * doubles stored so that they sort as integers; a string entry holds the
 * value from byte 22 plus `shift`.
 *
 * @param b {bytes} the entries and labels
 * @param head {Sas7Head} the header
 * @param capacity {int} the value entries
 * @param used {int} the labels
 * @param other {int} the `OTHER` label's position from 1, 0 if none
 * @param shift {int} how far string values are moved right
 * @param text {bool} whether the format is a character format
 * @return {map of string to string} value to label
 */
func sas7cLabels(
    b as bytes,
    head as Sas7Head,
    capacity as int,
    used as int,
    other as int,
    shift as int,
    text as bool) {
    def order as string init $head.order;
    def size as int init len($b);
    if ($capacity > $size // 6 or $used > $size // 11) {
        fail(io.sprintf("a format block of %d bytes cannot hold %d entries", $size, $capacity));
    }
    def entryAt as list of int init [];
    for (def i in 0..$used) {
        $entryAt[] = -1;
    }
    def at as int init 0;
    for (def i in 0..$capacity) {
        if ($at + 4 > $size) {
            fail("a format block ends inside its value entries");
        }
        if ($i < $used) {
            if ($at + 14 + $head.align > $size) {
                fail("a format block ends inside its value entries");
            }
            def label as int init binary.readUint($order, $b, $at + 10 + $head.align, 4);
            if ($label >= $used or $other > 0 and $label == $other - 1) {
                fail(io.sprintf("a value entry names label %d of %d", $label + 1, $used));
            }
            $entryAt[$label] = $at;
        }
        $at = $at + 6 + binary.readUint($order, $b, $at + 2, 2);
    }
    def out as map of string to string init {};
    for (def i in 0..$used) {
        if ($at + 10 > $size) {
            fail("a format block ends inside its labels");
        }
        def n as int init binary.readUint($order, $b, $at + 8, 2);
        if ($at + 10 + $n > $size) {
            fail("a format block ends inside a label");
        }
        def label as string init decodeText(
            binary.slice($b, $at + 10, $at + 10 + $n),
            $head.charset);
        $at = $at + 11 + $n;
        if ($other > 0 and $i == $other - 1) {
            continue;
        }
        def e as int init $entryAt[$i];
        if ($e < 0) {
            fail(io.sprintf("label %d of a format has no value", $i + 1));
        }
        if ($e + 30 > $size) {
            fail("a format block ends inside a value entry");
        }
        def entryEnd as int init $e + 6 + binary.readUint($order, $b, $e + 2, 2);
        if ($text) {
            if (22 + $shift > $entryEnd - $e or $entryEnd > $size) {
                fail("a format block ends inside a value entry");
            }
            $out[decodeText(binary.slice($b, $e + 22 + $shift, $entryEnd), $head.charset)] = $label;
            continue;
        }
        def start as int init binary.readInt("be", $b, $e + 22, 8);
        if ($entryEnd >= $e + 38 and $entryEnd <= $size and
            binary.readInt("be", $b, $e + 30, 8) != $start) {
            # a range of values: no single key
            continue;
        }
        $out[sas7cKey($start)] = $label;
    }
    return $out;
}

/**
 * The key of a catalog's numeric value: a special missing value's code, or
 * the number as `valueKey` writes it. A value is stored with its sign bit
 * flipped when positive and all bits flipped when negative; a missing
 * value is six bytes of 0xFF around its tag.
 *
 * @param raw {int} the stored 8 bytes, big-endian
 * @return {string} the key
 */
func sas7cKey(raw as int) {
    if (($raw | 0xFF0000000000) == 0xFFFFFFFFFFFF) {
        return sas7Tag(($raw >> 40) & 0xFF);
    }
    def bits as int init 0;
    if ($raw > 0) {
        $bits = ~ $raw;
    } else {
        $bits = $raw ^ SAS7C_SIGN;
    }
    def col as Sas7Column init sas7Numbers([$bits], "a format");
    if (len($col.missing) != 1 or $col.missing[0] != "") {
        fail("a format value that is not a number");
    }
    return valueKey($col.numbers[0]);
}

/**
 * The name of a format as a catalog keys it: the display format without
 * its width and decimals, upper-cased (`DATE9.` is `DATE`, `$sex1.` is
 * `$SEX`).
 *
 * @param format {string} a display format such as `Variable.format`
 * @return {string} the name, `""` for a format of no name (`8.2`)
 * @example
 *   statfiles.sasFormatName("$GENDER6.");   # "$GENDER"
 */
export func sasFormatName(format as string) {
    def m as regex.Match init regex.find(
        '^(\$?[A-Za-z_](?:[A-Za-z0-9_]*[A-Za-z_])?)[0-9]*\.[0-9]*$',
        $format);
    if ($m.start < 0) {
        return "";
    }
    return strings.upper($m.groups[0]);
}

/**
 * Attach a catalog's value labels to the variables whose format names a
 * format of the catalog (by `sasFormatName`, character formats to string
 * variables, others to numeric ones). Variables of other formats keep
 * their labels.
 *
 * @param ds {Dataset} the data set, as `readSas7bdat` returns it
 * @param catalog {map of string to map of string to string} from
 *   `readSas7bcat`
 * @return {Dataset} the data set with `valueLabels` filled in
 * @example
 *   $ds = statfiles.withSasLabels($ds, statfiles.readSas7bcat(fs.readBytes("formats.sas7bcat"), statfiles.options()));
 *   io.printf("%s\n", statfiles.labelOf($ds, "sex", 0));
 */
export func withSasLabels(ds as Dataset, catalog as map of string to map of string to string) {
    for (def i in 0..len($ds.variables)) {
        def name as string init sasFormatName($ds.variables[$i].format);
        if ($name == "" or not maps.has($catalog, $name)) {
            continue;
        }
        if (strings.startsWith($name, "$") == ($ds.variables[$i].type == "string")) {
            $ds.variables[$i].valueLabels = $catalog[$name];
        }
    }
    return $ds;
}
