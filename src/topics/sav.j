# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# statfiles - the sav topic: SPSS .sav and .zsav. Spliced into statfiles.j via include.
#
# A system file is a 176-byte header, the dictionary records (2 variable, 3+4
# value labels, 6 document, 7 extension, 999 end) and the cases: raw 8-byte
# slots, bytecode compressed, or (.zsav) bytecode compressed and then cut into
# zlib blocks. The cases are first brought to the raw slot layout, so every
# numeric column is one `binary.readFloats` call.

/** The SPSS format type names by their code in a print or write format; `""` is unused. */
def const SAV_FORMAT_NAMES as list of string init [
    "",
    "A",
    "AHEX",
    "COMMA",
    "DOLLAR",
    "F",
    "IB",
    "PIBHEX",
    "P",
    "PIB",
    "PK",
    "RB",
    "RBHEX",
    "",
    "",
    "Z",
    "N",
    "E",
    "",
    "",
    "DATE",
    "TIME",
    "DATETIME",
    "ADATE",
    "JDATE",
    "DTIME",
    "WKDAY",
    "MONTH",
    "MOYR",
    "QYR",
    "WKYR",
    "PCT",
    "DOT",
    "CCA",
    "CCB",
    "CCC",
    "CCD",
    "CCE",
    "EDATE",
    "SDATE",
    "MTIME",
    "YMDHMS"
];

/** A bytecode command block of eight raw-data codes (253), read as a little-endian int64. */
def const SAV_ALL_RAW as int init -144680345676153347;

/** The size of the file header. */
def const SAV_HEADER_SIZE as int init 176;

/** The data bytes a segment of a very long string carries, but the last. */
def const SAV_SEGMENT_BYTES as int init 255;

/** The width a segment of a very long string adds to the string, but the last. */
def const SAV_SEGMENT_WIDTH as int init 252;

/**
 * One variable record that is not a continuation: a numeric variable, a
 * string, or one segment of a very long string.
 *
 * @field name {bytes} the short name, blank padded
 * @field width {int} 0 numeric, else the string width (1 to 255)
 * @field slot {int} its first 8-byte slot in a case
 * @field label {bytes} the variable label, empty if none
 * @field print {int} the packed print format
 * @field missing {int} the missing-value code: 0 to 3 values, -2 a range,
 *   -3 a range and one value
 * @field missNum {list of float} the missing values of a numeric variable
 * @field missStr {list of bytes} the missing values of a string, 8 bytes each
 */
def struct SavRaw {
    name as bytes,
    width as int,
    slot as int,
    label as bytes,
    print as int,
    missing as int,
    missNum as list of float,
    missStr as list of bytes
};

/**
 * One value-label record (type 3) with the variables of its record 4.
 *
 * @field slots {list of int} the dictionary indexes of the variables, from 1
 * @field values {list of bytes} the values, 8 bytes each
 * @field labels {list of bytes} the labels
 */
def struct SavLabels {
    slots as list of int,
    values as list of bytes,
    labels as list of bytes
};

/**
 * The dictionary of a system file, its text still undecoded.
 *
 * @field order {string} `le` or `be`
 * @field zsav {bool} a `$FL3` file
 * @field compression {int} 0 none, 1 bytecode, 2 zlib
 * @field bias {float} the compression bias
 * @field cases {int} the case count, -1 when unknown
 * @field label {bytes} the file label
 * @field slots {int} the 8-byte slots in a case
 * @field raws {list of SavRaw} the variable records but continuations
 * @field slotRaw {list of int} per slot, the index in `raws` it starts, -1
 *   for a continuation
 * @field labelSets {list of SavLabels} the value-label records
 * @field charCode {int} the character code of record 7.3, 0 if none
 * @field charset {bytes} the encoding name of record 7.20, empty if none
 * @field sysmis {float} the system-missing value
 * @field highest {float} the value of HI in a missing range
 * @field lowest {float} the value of LO in a missing range
 * @field longNames {bytes} the text of record 7.13
 * @field veryLong {bytes} the text of record 7.14
 * @field longLabels {list of bytes} each record 7.21
 * @field longMissing {list of bytes} each record 7.22
 * @field dataStart {int} the offset of the cases (of the zlib header in a .zsav)
 */
def struct SavDict {
    order as string,
    zsav as bool,
    compression as int,
    bias as float,
    cases as int,
    label as bytes,
    slots as int,
    raws as list of SavRaw,
    slotRaw as list of int,
    labelSets as list of SavLabels,
    charCode as int,
    charset as bytes,
    sysmis as float,
    highest as float,
    lowest as float,
    longNames as bytes,
    veryLong as bytes,
    longLabels as list of bytes,
    longMissing as list of bytes,
    dataStart as int
};

/**
 * Whether the first bytes are those of this format.
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikeSav(data as bytes) {
    return binary.startsWith($data, encoding.encode("utf-8", "$FL2")) or
        binary.startsWith($data, encoding.encode("utf-8", "$FL3"));
}

/**
 * A 4-byte integer of the file.
 *
 * @param data {bytes} the file
 * @param order {string} `le` or `be`
 * @param pos {int} its offset
 * @param what {string} what it is, for the message
 * @return {int} the integer
 */
func savInt(data as bytes, order as string, pos as int, what as string) {
    need($data, $pos, 4, $what);
    return binary.readInt($order, $data, $pos, 4);
}

/**
 * An 8-byte floating-point number of the file; NaN and infinity are errors.
 *
 * @param data {bytes} the file
 * @param order {string} `le` or `be`
 * @param pos {int} its offset
 * @param what {string} what it is, for the message
 * @return {float} the number
 */
func savFloat(data as bytes, order as string, pos as int, what as string) {
    need($data, $pos, 8, $what);
    def x as float;
    try {
        $x = binary.readFloat($order, $data, $pos, 8);
    } catch (e) {
        fail("a value that is not a finite number in " + $what);
    }
    return $x;
}

/**
 * The text of a print format.
 *
 * @param t {int} the format type code
 * @param w {int} the width
 * @param d {int} the decimals
 * @return {string} the format, such as `F8.2`, `A20` or `DATE11`; `""` for
 *   type 0
 */
func savFormatOf(t as int, w as int, d as int) {
    if ($t == 0) {
        return "";
    }
    if ($t < 0 or $t >= len(SAV_FORMAT_NAMES) or SAV_FORMAT_NAMES[$t] == "") {
        fail(io.sprintf("an unknown display format type %d", $t));
    }
    def kind as string init SAV_FORMAT_NAMES[$t];
    if ($t == 1 or $t == 2) {
        return "{$kind}{$w}";
    }
    if ($d > 0 or $t == 5) {
        return "{$kind}{$w}.{$d}";
    }
    return "{$kind}{$w}";
}

/**
 * The text of a packed print format (type << 16 | width << 8 | decimals).
 *
 * @param code {int} the packed format
 * @return {string} the format
 */
func savFormat(code as int) {
    return savFormatOf(($code >> 16) & 255, ($code >> 8) & 255, $code & 255);
}

/**
 * Read the header and the dictionary.
 *
 * @param data {bytes} the file
 * @return {SavDict} the dictionary
 */
func savDictionary(data as bytes) {
    need($data, 0, SAV_HEADER_SIZE, "the file header");
    def zsav as bool init binary.startsWith($data, encoding.encode("utf-8", "$FL3"));
    if (not $zsav and not binary.startsWith($data, encoding.encode("utf-8", "$FL2"))) {
        fail("not an SPSS system file");
    }
    def o as string init "le";
    def layout as int init binary.readInt("le", $data, 64, 4);
    if ($layout != 2 and $layout != 3) {
        $o = "be";
        $layout = binary.readInt("be", $data, 64, 4);
        if ($layout != 2 and $layout != 3) {
            fail("a header of an unknown byte order");
        }
    }
    def nominal as int init binary.readInt($o, $data, 68, 4);
    def compression as int init binary.readInt($o, $data, 72, 4);
    if ($zsav and $compression != 2 or not $zsav and $compression != 0 and $compression != 1) {
        fail(io.sprintf("the compression code %d", $compression));
    }
    def d as SavDict init SavDict{
        order: $o,
        zsav: $zsav,
        compression: $compression,
        bias: savFloat($data, $o, 84, "the file header"),
        cases: binary.readInt($o, $data, 80, 4),
        label: $data[109..173],
        slots: 0,
        raws: [],
        slotRaw: [],
        labelSets: [],
        charCode: 0,
        charset: binary.make(0),
        sysmis: LOWEST,
        highest: HIGHEST,
        lowest: -1.7976931348623155e308,
        longNames: binary.make(0),
        veryLong: binary.make(0),
        longLabels: [],
        longMissing: [],
        dataStart: 0
    };
    if ($d.cases < -1) {
        fail(io.sprintf("the case count %d", $d.cases));
    }
    def pos as int init SAV_HEADER_SIZE;
    def pending as int init 0;
    def done as bool init false;
    while (not $done) {
        def rec as int init savInt($data, $o, $pos, "a record type");
        $pos = $pos + 4;
        if ($pending > 0 and ($rec != 2 or savInt($data, $o, $pos, "a variable record") != -1)) {
            fail(io.sprintf("a string variable lacks %d continuation records", $pending));
        }
        match ($rec) {
            when 2 {
                need($data, $pos, 28, "a variable record");
                def typ as int init binary.readInt($o, $data, $pos, 4);
                def hasLabel as int init binary.readInt($o, $data, $pos + 4, 4);
                def nmiss as int init binary.readInt($o, $data, $pos + 8, 4);
                def raw as SavRaw init SavRaw{
                    name: $data[$pos + 20..$pos + 28],
                    width: $typ,
                    slot: $d.slots,
                    label: binary.make(0),
                    print: binary.readInt($o, $data, $pos + 12, 4),
                    missing: $nmiss,
                    missNum: [],
                    missStr: []
                };
                $pos = $pos + 28;
                if ($hasLabel == 1) {
                    def n as int init savInt($data, $o, $pos, "a variable label");
                    if ($n < 0) {
                        fail("a negative variable label length");
                    }
                    need($data, $pos + 4, ($n + 3) // 4 * 4, "a variable label");
                    $raw.label = $data[$pos + 4..$pos + 4 + $n];
                    $pos = $pos + 4 + ($n + 3) // 4 * 4;
                } elseif ($hasLabel != 0) {
                    fail(io.sprintf("a variable label flag %d", $hasLabel));
                }
                def count as int init $nmiss;
                if ($nmiss == -2 or $nmiss == -3) {
                    $count = -$nmiss;
                    if ($typ != 0) {
                        fail("a missing range on a string variable");
                    }
                } elseif ($nmiss < 0 or $nmiss > 3) {
                    fail(io.sprintf("a missing-value count %d", $nmiss));
                }
                need($data, $pos, $count * 8, "the missing values");
                for (def k in 0..$count) {
                    if ($typ == 0) {
                        $raw.missNum[] = savFloat($data, $o, $pos + $k * 8, "a missing value");
                    } else {
                        $raw.missStr[] = $data[$pos + $k * 8..$pos + $k * 8 + 8];
                    }
                }
                $pos = $pos + $count * 8;
                if ($typ == -1) {
                    if ($pending == 0) {
                        fail("a continuation record that follows no string variable");
                    }
                    $pending = $pending - 1;
                    $d.slotRaw[] = -1;
                } elseif ($typ >= 0 and $typ <= 255) {
                    $d.slotRaw[] = len($d.raws);
                    $d.raws[] = $raw;
                    if ($typ > 0) {
                        $pending = ($typ + 7) // 8 - 1;
                    }
                } else {
                    fail(io.sprintf("a variable type %d", $typ));
                }
                $d.slots = $d.slots + 1;
            }
            when 3 {
                def n as int init savInt($data, $o, $pos, "a value-label record");
                $pos = $pos + 4;
                if ($n < 0) {
                    fail("a negative value-label count");
                }
                def set as SavLabels init SavLabels{slots: [], values: [], labels: []};
                for (def k in 0..$n) {
                    need($data, $pos, 9, "a value label");
                    def ll as int init $data[$pos + 8];
                    def padded as int init ($ll + 8) // 8 * 8;
                    need($data, $pos + 8, $padded, "a value label");
                    $set.values[] = $data[$pos..$pos + 8];
                    $set.labels[] = $data[$pos + 9..$pos + 9 + $ll];
                    $pos = $pos + 8 + $padded;
                }
                if (savInt($data, $o, $pos, "a value-label variables record") != 4) {
                    fail("value labels not followed by their variables");
                }
                def nv as int init savInt($data, $o, $pos + 4, "a value-label variables record");
                $pos = $pos + 8;
                if ($nv < 1) {
                    fail(io.sprintf("value labels for %d variables", $nv));
                }
                need($data, $pos, $nv * 4, "a value-label variables record");
                $set.slots = binary.readInts($o, $data, $pos, $nv, 4);
                $pos = $pos + $nv * 4;
                $d.labelSets[] = $set;
            }
            when 6 {
                def n as int init savInt($data, $o, $pos, "a document record");
                if ($n < 0) {
                    fail("a negative document line count");
                }
                need($data, $pos + 4, $n * 80, "a document record");
                $pos = $pos + 4 + $n * 80;
            }
            when 7 {
                need($data, $pos, 12, "an extension record");
                def sub as int init binary.readInt($o, $data, $pos, 4);
                def size as int init binary.readInt($o, $data, $pos + 4, 4);
                def count as int init binary.readInt($o, $data, $pos + 8, 4);
                $pos = $pos + 12;
                if ($size < 0 or $count < 0 or $count > 0 and $size > (len($data) - $pos) / $count) {
                    fail(io.sprintf("the extension record %d ends past the file", $sub));
                }
                def total as int init $size * $count;
                need($data, $pos, $total, "an extension record");
                match ($sub) {
                    when 3 {
                        if ($size != 4 or $count != 8) {
                            fail("a machine integer record of the wrong size");
                        }
                        $d.charCode = binary.readInt($o, $data, $pos + 28, 4);
                    }
                    when 4 {
                        if ($size != 8 or $count != 3) {
                            fail("a machine floating-point record of the wrong size");
                        }
                        $d.sysmis = savFloat($data, $o, $pos, "the machine floating-point record");
                        $d.highest = savFloat(
                            $data,
                            $o,
                            $pos + 8,
                            "the machine floating-point record");
                        $d.lowest = savFloat(
                            $data,
                            $o,
                            $pos + 16,
                            "the machine floating-point record");
                    }
                    when 13 { $d.longNames = $data[$pos..$pos + $total]; }
                    when 14 { $d.veryLong = $data[$pos..$pos + $total]; }
                    when 16 {
                        if ($size != 8 or $count != 2) {
                            fail("an extended case count record of the wrong size");
                        }
                        if ($d.cases == -1) {
                            $d.cases = binary.readInt($o, $data, $pos + 8, 8);
                            if ($d.cases < -1) {
                                fail(io.sprintf("the case count %d", $d.cases));
                            }
                        }
                    }
                    when 20 { $d.charset = $data[$pos..$pos + $total]; }
                    when 21 { $d.longLabels[] = $data[$pos..$pos + $total]; }
                    when 22 { $d.longMissing[] = $data[$pos..$pos + $total]; }
                }
                $pos = $pos + $total;
            }
            when 999 {
                need($data, $pos, 4, "the dictionary end record");
                $pos = $pos + 4;
                $done = true;
            }
            else { fail(io.sprintf("an unknown record type %d at offset %d", $rec, $pos - 4)); }
        }
    }
    if (len($d.raws) == 0) {
        fail("a file without variables");
    }
    if ($nominal != -1 and $nominal != $d.slots) {
        fail(io.sprintf("a case size of %d slots for %d variable records", $nominal, $d.slots));
    }
    $d.dataStart = $pos;
    return $d;
}

/**
 * The `encoding` codec of a code page number from the machine integer record.
 *
 * @param code {int} the character code
 * @return {string} the codec name
 */
func savCodePage(code as int) {
    if ($code == 2 or $code == 20127) {
        return "ascii";
    }
    if ($code == 3) {
        return "windows-1252";
    }
    if ($code == 65001) {
        return "utf-8";
    }
    if ($code >= 28591 and $code <= 28599) {
        return io.sprintf("iso-8859-%d", $code - 28590);
    }
    if ($code == 28603 or $code == 28605) {
        return io.sprintf("iso-8859-%d", $code - 28590);
    }
    if ($code == 1) {
        return charsetName("ebcdic");
    }
    return charsetName(io.sprintf("cp%d", $code));
}

/**
 * The character set of the text: the option, else the encoding record, else
 * the code page of the machine integer record, else windows-1252.
 *
 * @param d {SavDict} the dictionary
 * @param opts {Options} the options
 * @return {string} an `encoding` codec name, or `utf-8`
 */
func savCharset(d as SavDict, opts as Options) {
    if ($opts.encoding != "") {
        return charsetName($opts.encoding);
    }
    if (len($d.charset) > 0) {
        return charsetName(encoding.decode("iso-8859-1", untilNul($d.charset)));
    }
    if ($d.charCode != 0) {
        return savCodePage($d.charCode);
    }
    return "windows-1252";
}

/**
 * Split the `KEY=VALUE` pairs of a long-names or very-long-string record.
 *
 * @param text {bytes} the record
 * @param cs {string} the character set
 * @param what {string} the record, for the message
 * @return {list of string} the keys and values, alternating
 */
func savPairs(text as bytes, cs as string, what as string) {
    def out as list of string init [];
    def s as string init strings.replace(decodeText($text, $cs), "\0", "");
    for (def item in strings.split($s, "\t")) {
        if ($item == "") {
            continue;
        }
        def at as int init strings.indexOf($item, "=");
        if ($at < 1) {
            fail("a malformed entry in the " + $what);
        }
        $out[] = $item[..$at];
        $out[] = $item[$at + 1..len($item)];
    }
    return $out;
}

/**
 * A missing value of a numeric variable as its range end: LO and HI become
 * `LOWEST` and `HIGHEST`.
 *
 * @param x {float} the stored value
 * @param d {SavDict} the dictionary
 * @return {float} the range end
 */
func savRangeEnd(x as float, d as SavDict) {
    if ($x == $d.lowest or $x == LOWEST) {
        return LOWEST;
    }
    if ($x == $d.highest) {
        return HIGHEST;
    }
    return $x;
}

/**
 * The 8 bytes of a floating-point number in a byte order (normal numbers and
 * zero), for the bytecode table.
 *
 * @param x {float} the number
 * @param order {string} `le` or `be`
 * @return {bytes} its IEEE 754 binary64 form
 */
func savEncodeFloat(x as float, order as string) {
    def out as bytes init binary.make(8);
    if ($x == 0.0) {
        return $out;
    }
    def sign as int init 0;
    def a as float init $x;
    if ($a < 0.0) {
        $sign = 128;
        $a = -$a;
    }
    def e as int init math.min(math.floor(math.log2($a)), 1023);
    while ($e > -1022 and math.pow(2.0, $e) > $a) {
        $e = $e - 1;
    }
    while ($e < 1023 and math.pow(2.0, $e + 1) <= $a) {
        $e = $e + 1;
    }
    if ($e < -1022 or math.pow(2.0, $e) > $a) {
        fail("a compression bias out of range");
    }
    def frac as int init math.floor(($a / math.pow(2.0, $e) - 1.0) * 4503599627370496.0);
    def be as int init $e + 1023;
    $out[0] = $sign | ($be >> 4);
    $out[1] = (($be & 15) << 4) | ($frac >> 48);
    for (def k in 2..8) {
        $out[$k] = ($frac >> (56 - 8 * $k)) & 255;
    }
    if ($order == "le") {
        def le as bytes init binary.make(8);
        for (def k in 0..8) {
            $le[$k] = $out[7 - $k];
        }
        $out = $le;
    }
    if (binary.readFloat($order, $out, 0, 8) != $x) {
        fail("a compression bias out of range");
    }
    return $out;
}

/**
 * Undo the bytecode compression: the cases in the raw slot layout.
 *
 * @param buf {bytes} the compressed stream
 * @param start {int} where it starts in `buf`
 * @param d {SavDict} the dictionary
 * @param nvars {int} the variables, for the cell cap
 * @param opts {Options} the options
 * @return {bytes} the cases, 8 bytes per slot
 */
func savBytecode(buf as bytes, start as int, d as SavDict, nvars as int, opts as Options) {
    # the 8 bytes of each numeric code, made when first met
    def tbl as list of bytes init [];
    for (def c in 0..256) {
        $tbl[] = binary.make(0);
    }
    def spaces as bytes init binary.make(8, 32);
    def isText as list of bool init [];
    for (def ri in $d.slotRaw) {
        $isText[] = $ri < 0 or $d.raws[$ri].width > 0;
    }
    # the unpacked cases count against maxBytes as well as maxCells: one
    # code byte can stand for 8 bytes, so a long string's slots grow 8-fold
    def byteRows as int init $opts.maxBytes // ($d.slots * 8);
    if ($d.cases > $byteRows) {
        savOverBytes($d, $opts);
    }
    def maxRows as int init $d.cases;
    if ($maxRows < 0) {
        $maxRows = math.min($opts.maxCells // $nvars, $byteRows);
    }
    def parts as list of bytes init [];
    def chunks as list of bytes init [];
    def n as int init len($buf);
    def p as int init $start;
    def block as int init 0;
    def ci as int init 8;
    def slot as int init 0;
    def rows as int init 0;
    def slots as int init $d.slots;
    def cases as int init $d.cases;
    def run as int init -1;
    def going as bool init $cases != 0;
    while ($going) {
        if ($ci == 8) {
            if ($run >= 0) {
                $parts[] = $buf[$run..$p];
                $run = -1;
            }
            if ($p == $n and $slot == 0 and $cases < 0) {
                break;
            }
            if ($p + 8 > $n) {
                fail(io.sprintf("the compressed data ends inside case %d", $rows + 1));
            }
            $block = $p;
            $p = $p + 8;
            $ci = 0;
            # fast path: eight raw slots, none past the declared cases
            if ($p + 64 <= $n and binary.readInt("le", $buf, $block, 8) == SAV_ALL_RAW and
                ($cases < 0 or $rows * $slots + $slot + 8 <= $cases * $slots)) {
                $parts[] = $buf[$p..$p + 64];
                $p = $p + 64;
                $ci = 8;
                $slot = $slot + 8;
                while ($slot >= $slots) {
                    $slot = $slot - $slots;
                    $rows = $rows + 1;
                }
                if ($rows > $maxRows) {
                    savOverCap($rows, $byteRows, $d, $opts);
                }
                $going = $rows != $cases or $slot != 0;
                continue;
            }
        }
        def c as int init $buf[$block + $ci];
        $ci = $ci + 1;
        if ($c == 253) {
            if ($p + 8 > $n) {
                fail(io.sprintf("the compressed data ends inside case %d", $rows + 1));
            }
            if ($run < 0) {
                $run = $p;
            }
            $p = $p + 8;
        } elseif ($c == 0) {
            continue;
        } else {
            if ($run >= 0) {
                $parts[] = $buf[$run..$p];
                $run = -1;
            }
            if ($c == 254) {
                if (not $isText[$slot]) {
                    fail("the compression code 254 for a number");
                }
                $parts[] = $spaces;
            } elseif ($c == 252) {
                if ($slot != 0 or $cases >= 0) {
                    fail(io.sprintf("the compressed data ends inside case %d", $rows + 1));
                }
                break;
            } else {
                if ($isText[$slot]) {
                    fail(io.sprintf("the compression code %d for a string", $c));
                }
                if (len($tbl[$c]) == 0) {
                    $tbl[$c] = savCodeBytes($c, $d);
                }
                $parts[] = $tbl[$c];
            }
        }
        $slot = $slot + 1;
        if ($slot == $slots) {
            $slot = 0;
            $rows = $rows + 1;
            if ($rows > $maxRows) {
                savOverCap($rows, $byteRows, $d, $opts);
            }
            $going = $rows != $cases;
            if (len($parts) >= 65536) {
                # few large pieces instead of millions of 8-byte ones
                $chunks[] = binary.join($parts);
                $parts = [];
            }
        }
    }
    if ($run >= 0) {
        $parts[] = $buf[$run..$p];
    }
    savCheckTail($buf, $block, $ci, $p);
    $chunks[] = binary.join($parts);
    return binary.join($chunks);
}

/**
 * Throw `"limit"` for bytecode that unpacks to more rows than a cap allows.
 *
 * @param rows {int} the rows unpacked so far
 * @param byteRows {int} the most rows `Options.maxBytes` allows
 * @param d {SavDict} the dictionary
 * @param opts {Options} the options
 */
func savOverCap(rows as int, byteRows as int, d as SavDict, opts as Options) {
    if ($rows > $byteRows) {
        savOverBytes($d, $opts);
    }
    failLimit(io.sprintf("over %d cells", $opts.maxCells));
}

/**
 * Throw `"limit"` for cases that unpack to more than `Options.maxBytes`.
 *
 * @param d {SavDict} the dictionary
 * @param opts {Options} the options
 */
func savOverBytes(d as SavDict, opts as Options) {
    failLimit(io.sprintf(
        "the cases unpack to over %d bytes (%d per case)",
        $opts.maxBytes,
        $d.slots * 8));
}

/**
 * The 8 bytes a numeric bytecode stands for: `code - bias`, or
 * system-missing for 255.
 *
 * @param code {int} the code, 1 to 251 or 255
 * @param d {SavDict} the dictionary
 * @return {bytes} the number in the file's byte order
 */
func savCodeBytes(code as int, d as SavDict) {
    if ($code == 255) {
        return savEncodeFloat($d.sysmis, $d.order);
    }
    return savEncodeFloat(convert.toFloat($code) - $d.bias, $d.order);
}

/**
 * Refuse data after the last case of a bytecode stream: the rest of the
 * command block may hold only padding (0) and end-of-data (252) codes, and
 * one more block may follow only when it starts with end-of-data.
 *
 * @param buf {bytes} the compressed stream
 * @param block {int} the offset of the current command block
 * @param ci {int} the next code in it
 * @param p {int} the offset after its data
 */
func savCheckTail(buf as bytes, block as int, ci as int, p as int) {
    def k as int init $ci;
    while ($k < 8 and $block + $k < len($buf)) {
        def c as int init $buf[$block + $k];
        if ($c != 0 and $c != 252) {
            fail("compressed data after the last case");
        }
        $k = $k + 1;
    }
    if ($p == len($buf)) {
        return;
    }
    if ($p + 8 > len($buf) or $buf[$p] != 252) {
        fail("data after the last case");
    }
    for (def j in 1..8) {
        if ($buf[$p + $j] != 0 and $buf[$p + $j] != 252) {
            fail("data after the last case");
        }
    }
    if ($p + 8 != len($buf)) {
        fail("data after the last case");
    }
}

/**
 * Unpack the zlib blocks of a .zsav into the bytecode stream.
 *
 * @param data {bytes} the file
 * @param d {SavDict} the dictionary
 * @param opts {Options} the options; `maxBytes` caps the unpacked size
 * @return {bytes} the bytecode stream
 */
func savUnzip(data as bytes, d as SavDict, opts as Options) {
    def o as string init $d.order;
    def zh as int init $d.dataStart;
    need($data, $zh, 24, "the zlib header");
    def zt as int init binary.readInt($o, $data, $zh + 8, 8);
    def ztLen as int init binary.readInt($o, $data, $zh + 16, 8);
    if (binary.readInt($o, $data, $zh, 8) != $zh) {
        fail("a zlib header that does not give its own offset");
    }
    if ($zt < $zh + 24 or $ztLen < 24 or $ztLen % 24 != 0 or $zt > len($data) or
        $ztLen != len($data) - $zt) {
        fail("a zlib trailer that does not end the file");
    }
    def blockSize as int init binary.readInt($o, $data, $zt + 16, 4);
    def nblocks as int init binary.readInt($o, $data, $zt + 20, 4);
    if (convert.toFloat(binary.readInt($o, $data, $zt, 8)) != -$d.bias or
        binary.readInt($o, $data, $zt + 8, 8) != 0) {
        fail("a zlib trailer that does not match the header");
    }
    if ($nblocks != $ztLen // 24 - 1 or $blockSize <= 0) {
        fail("a zlib trailer of the wrong size");
    }
    def uofs as int init $zh;
    def cofs as int init $zh + 24;
    def total as int init 0;
    def entries as list of int init [];
    for (def k in 0..$nblocks) {
        def e as int init $zt + 24 + 24 * $k;
        def u as int init binary.readInt($o, $data, $e + 16, 4);
        def c as int init binary.readInt($o, $data, $e + 20, 4);
        if (binary.readInt($o, $data, $e, 8) != $uofs or
            binary.readInt($o, $data, $e + 8, 8) != $cofs) {
            fail(io.sprintf("the zlib block %d is not where the trailer says", $k));
        }
        if ($u < 0 or $u > $blockSize or $k < $nblocks - 1 and $u != $blockSize or $c < 0 or
            $c > $zt - $cofs) {
            fail(io.sprintf("the zlib block %d has a wrong size", $k));
        }
        $entries[] = $cofs;
        $entries[] = $c;
        $entries[] = $u;
        $uofs = $uofs + $u;
        $cofs = $cofs + $c;
        $total = $total + $u;
    }
    if ($cofs != $zt) {
        fail("the zlib blocks do not end at the trailer");
    }
    if ($total > $opts.maxBytes) {
        failLimit(io.sprintf("the data unpacks to %d bytes, over %d", $total, $opts.maxBytes));
    }
    def parts as list of bytes init [];
    def used as int init 0;
    for (def k in 0..$nblocks) {
        def at as int init $entries[3 * $k];
        def size as int init $entries[3 * $k + 2];
        def out as bytes;
        # what is left of the budget; never 0, which unpackWith reads as its
        # default cap
        def left as int init $opts.maxBytes - $used;
        if ($left < 1) {
            $left = 1;
        }
        try {
            $out = compress.unpackWith(
                "zlib",
                $data[$at..$at + $entries[3 * $k + 1]],
                compress.UnpackOptions{maxBytes: $left});
        } catch (e) {
            if ($e.kind == "limit") {
                throw $e;
            }
            fail(io.sprintf("the zlib block %d does not unpack", $k));
        }
        if (len($out) != $size) {
            fail(io.sprintf("the zlib block %d unpacks to %d bytes, not %d", $k, len($out), $size));
        }
        $used = $used + $size;
        $parts[] = $out;
    }
    return binary.join($parts);
}

/**
 * Read a SPSS .sav and .zsav file.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {Dataset} its contents
 * @throws {Error} kind `"statfiles"` for a malformed file, `"limit"` over a cap
 */
export func readSav(data as bytes, opts as Options) {
    checkSize($opts, 0, 0);
    def d as SavDict init savDictionary($data);
    def cs as string init savCharset($d, $opts);
    def nraw as int init len($d.raws);
    def short as list of string init [];
    def shortAt as map of string to int init {};
    for (def r in 0..$nraw) {
        def s as string init decodeText($d.raws[$r].name, $cs);
        $short[] = $s;
        if (not maps.has($shortAt, $s)) {
            $shortAt[$s] = $r;
        }
    }

    # very long strings: a variable of more than 255 bytes is one 255-wide
    # segment record per 252 bytes of width, folded back into one variable
    def vlw as map of string to int init {};
    def pairs as list of string init savPairs($d.veryLong, $cs, "very long string record");
    for (def k in 0..len($pairs) // 2) {
        def wtext as string init $pairs[2 * $k + 1];
        if (not regex.matches('^[0-9]{1,5}$', $wtext)) {
            fail("a malformed width in the very long string record");
        }
        $vlw[$pairs[2 * $k]] = convert.toInt($wtext);
    }
    def firstRaw as list of int init [];
    def widths as list of int init [];
    def rawVar as list of int init [];
    def matched as int init 0;
    def r as int init 0;
    while ($r < $nraw) {
        def w as int init $d.raws[$r].width;
        def n as int init 1;
        if (maps.has($vlw, $short[$r])) {
            $w = $vlw[$short[$r]];
            $n = ($w + SAV_SEGMENT_WIDTH - 1) // SAV_SEGMENT_WIDTH;
            if ($w <= 255 or $d.raws[$r].width != 255 or $r + $n > $nraw) {
                fail("the very long string " + $short[$r] + " does not match its segments");
            }
            for (def k in 1..$n) {
                def want as int init 255;
                if ($k == $n - 1) {
                    $want = $w - SAV_SEGMENT_WIDTH * ($n - 1);
                }
                if ($d.raws[$r + $k].width != $want) {
                    fail("the very long string " + $short[$r] + " does not match its segments");
                }
            }
            $matched = $matched + 1;
        }
        $rawVar[] = len($firstRaw);
        for (def k in 1..$n) {
            $rawVar[] = -1;
        }
        $firstRaw[] = $r;
        $widths[] = $w;
        $r = $r + $n;
    }
    if ($matched != len($vlw)) {
        fail("the very long string record names a variable the file lacks");
    }
    def nvars as int init len($firstRaw);

    # long names
    def longOf as map of string to string init {};
    $pairs = savPairs($d.longNames, $cs, "long variable names record");
    for (def k in 0..len($pairs) // 2) {
        if (not maps.has($shortAt, $pairs[2 * $k])) {
            fail("the long variable names record names a variable the file lacks");
        }
        $longOf[$pairs[2 * $k]] = $pairs[2 * $k + 1];
    }

    def vars as list of Variable init [];
    def nameAt as map of string to int init {};
    def hasRange as list of bool init [];
    for (def i in 0..$nvars) {
        def raw as SavRaw init $d.raws[$firstRaw[$i]];
        def vname as string init $short[$firstRaw[$i]];
        if (maps.has($longOf, $vname)) {
            $vname = $longOf[$vname];
        }
        def v as Variable init Variable{
            name: $vname,
            label: decodeText($raw.label, $cs),
            type: "numeric",
            storage: "numeric",
            width: 8,
            format: savFormat($raw.print),
            valueLabels: {},
            missingValues: [],
            missingRange: []
        };
        if ($raw.width > 0) {
            $v.type = "string";
            $v.storage = "string";
            $v.width = $widths[$i];
            if ($widths[$i] > 255) {
                $v.format = "A{$widths[$i]}";
            }
            for (def m in $raw.missStr) {
                $v.missingValues[] = decodeText($m, $cs);
            }
        } else {
            def first as int init 0;
            if ($raw.missing < 0) {
                $v.missingRange = [
                    savRangeEnd($raw.missNum[0], $d),
                    savRangeEnd($raw.missNum[1], $d)
                ];
                $first = 2;
            }
            for (def k in $first..len($raw.missNum)) {
                $v.missingValues[] = valueKey($raw.missNum[$k]);
            }
        }
        $hasRange[] = len($v.missingRange) > 0;
        $vars[] = $v;
        $nameAt[$vname] = $i;
    }

    # value labels (record 3 + 4)
    for (def set in $d.labelSets) {
        def targets as list of int init [];
        def textual as bool init false;
        for (def k in 0..len($set.slots)) {
            def s as int init $set.slots[$k] - 1;
            if ($s < 0 or $s >= $d.slots or $d.slotRaw[$s] < 0 or $rawVar[$d.slotRaw[$s]] < 0) {
                fail(io.sprintf(
                    "value labels for the dictionary index %d, which starts no variable",
                    $s + 1));
            }
            def ri as int init $d.slotRaw[$s];
            def isText as bool init $d.raws[$ri].width > 0;
            if ($k > 0 and $isText != $textual) {
                fail("value labels shared by numeric and string variables");
            }
            if ($isText and $d.raws[$ri].width > 8) {
                fail("a value-label record for a string longer than 8 bytes");
            }
            $textual = $isText;
            $targets[] = $rawVar[$ri];
        }
        for (def k in 0..len($set.values)) {
            def key as string;
            if ($textual) {
                $key = decodeText($set.values[$k], $cs);
            } else {
                $key = valueKey(savFloat($set.values[$k], $d.order, 0, "a value label"));
            }
            def lab as string init decodeText($set.labels[$k], $cs);
            for (def vi in $targets) {
                $vars[$vi].valueLabels[$key] = $lab;
            }
        }
    }

    # long string value labels (7.21)
    for (def rec in $d.longLabels) {
        def p as int init 0;
        while ($p < len($rec)) {
            def vi as int init savLongVar(
                $rec,
                $d.order,
                $p,
                $cs,
                $nameAt,
                "long string value labels");
            $p = $p + 4 + binary.readInt($d.order, $rec, $p, 4);
            def w as int init savInt($rec, $d.order, $p, "long string value labels");
            def n as int init savInt($rec, $d.order, $p + 4, "long string value labels");
            $p = $p + 8;
            if ($vars[$vi].type != "string" or $w != $vars[$vi].width or $n < 0) {
                fail("long string value labels that do not fit " + $vars[$vi].name);
            }
            for (def k in 0..$n) {
                def vl as int init savInt($rec, $d.order, $p, "long string value labels");
                need($rec, $p + 4, $vl, "long string value labels");
                if ($vl < 0) {
                    fail("a negative length in the long string value labels");
                }
                def key as string init decodeText($rec[$p + 4..$p + 4 + $vl], $cs);
                $p = $p + 4 + $vl;
                def ll as int init savInt($rec, $d.order, $p, "long string value labels");
                need($rec, $p + 4, $ll, "long string value labels");
                if ($ll < 0) {
                    fail("a negative length in the long string value labels");
                }
                $vars[$vi].valueLabels[$key] = decodeText($rec[$p + 4..$p + 4 + $ll], $cs);
                $p = $p + 4 + $ll;
            }
        }
    }

    # long string missing values (7.22)
    for (def rec in $d.longMissing) {
        def p as int init 0;
        while ($p < len($rec)) {
            def vi as int init savLongVar(
                $rec,
                $d.order,
                $p,
                $cs,
                $nameAt,
                "long string missing values");
            $p = $p + 4 + binary.readInt($d.order, $rec, $p, 4);
            need($rec, $p, 5, "long string missing values");
            def n as int init $rec[$p];
            def vl as int init binary.readInt($d.order, $rec, $p + 1, 4);
            $p = $p + 5;
            if ($vars[$vi].type != "string" or $n < 1 or $n > 3 or $vl < 1) {
                fail("long string missing values that do not fit " + $vars[$vi].name);
            }
            need($rec, $p, $n * $vl, "long string missing values");
            for (def k in 0..$n) {
                $vars[$vi].missingValues[] = decodeText($rec[$p..$p + $vl], $cs);
                $p = $p + $vl;
            }
        }
    }

    # the cases, in the raw slot layout
    def flat as bytes;
    def base as int init 0;
    def rows as int init $d.cases;
    def caseSize as int init $d.slots * 8;
    if ($d.cases >= 0) {
        checkSize($opts, $d.cases, $nvars);
    }
    if ($d.compression == 0) {
        def avail as int init len($data) - $d.dataStart;
        if ($rows < 0) {
            if ($avail % $caseSize != 0) {
                fail("the data ends inside a case");
            }
            $rows = $avail // $caseSize;
            checkSize($opts, $rows, $nvars);
        } elseif ($avail < $rows * $caseSize) {
            fail(io.sprintf("the data ends inside case %d of %d", $avail // $caseSize + 1, $rows));
        } elseif ($avail > $rows * $caseSize) {
            fail("data after the last case");
        }
        $flat = $data;
        $base = $d.dataStart;
    } else {
        if ($d.compression == 1) {
            $flat = savBytecode($data, $d.dataStart, $d, $nvars, $opts);
        } else {
            $flat = savBytecode(savUnzip($data, $d, $opts), 0, $d, $nvars, $opts);
        }
        $rows = len($flat) // $caseSize;
    }

    def numbers as list of list of float init [];
    def texts as list of list of string init [];
    def missing as list of list of string init [];
    for (def i in 0..$nvars) {
        def raw as SavRaw init $d.raws[$firstRaw[$i]];
        def miss as list of string init [];
        if ($raw.width == 0) {
            def vals as list of float init savFloats(
                $flat,
                $d.order,
                $base + $raw.slot * 8,
                $rows,
                $caseSize,
                $vars[$i].name);
            def keys as list of string init $vars[$i].missingValues;
            def user as list of float init [];
            for (def k in 0..len($keys)) {
                $user[] = $raw.missNum[len($raw.missNum) - len($keys) + $k];
            }
            def lo as float init 0.0;
            def hi as float init 0.0;
            if ($hasRange[$i]) {
                $lo = $raw.missNum[0];
                $hi = $raw.missNum[1];
            }
            def sm as float init $d.sysmis;
            def hits as list of int init [];
            def row as int init 0;
            if (len($user) == 0 and not $hasRange[$i]) {
                for (def x in $vals) {
                    if ($x == $sm) {
                        $miss[] = MISSING_SYSTEM;
                        $hits[] = $row;
                    } else {
                        $miss[] = "";
                    }
                    $row = $row + 1;
                }
            } else {
                for (def x in $vals) {
                    if ($x == $sm) {
                        $miss[] = MISSING_SYSTEM;
                        $hits[] = $row;
                    } elseif ($hasRange[$i] and $x >= $lo and $x <= $hi or lists.contains(
                        $user,
                        $x)) {
                        $miss[] = MISSING_USER;
                    } else {
                        $miss[] = "";
                    }
                    $row = $row + 1;
                }
            }
            for (def h in $hits) {
                $vals[$h] = 0.0;
            }
            $numbers[] = $vals;
            $texts[] = [];
        } else {
            def segSlots as list of int init [];
            def segSizes as list of int init [];
            def w as int init $widths[$i];
            def nseg as int init 1;
            if ($w > 255) {
                $nseg = ($w + SAV_SEGMENT_WIDTH - 1) // SAV_SEGMENT_WIDTH;
            }
            for (def k in 0..$nseg) {
                def seg as SavRaw init $d.raws[$firstRaw[$i] + $k];
                $segSlots[] = $seg.slot * 8;
                if ($k < $nseg - 1) {
                    $segSizes[] = SAV_SEGMENT_BYTES;
                } else {
                    $segSizes[] = $seg.width;
                }
            }
            def keys as list of string init $vars[$i].missingValues;
            def col as list of string init [];
            for (def row in 0..$rows) {
                def at as int init $base + $row * $caseSize;
                def cell as bytes;
                if ($nseg == 1) {
                    $cell = $flat[$at + $segSlots[0]..$at + $segSlots[0] + $w];
                } else {
                    def pieces as list of bytes init [];
                    for (def k in 0..$nseg) {
                        $pieces[] = $flat[$at + $segSlots[$k]..$at + $segSlots[$k] + $segSizes[$k]];
                    }
                    $cell = binary.join($pieces)[..$w];
                }
                def s as string init decodeText($cell, $cs);
                $col[] = $s;
                if (len($keys) > 0 and lists.contains($keys, $s)) {
                    $miss[] = MISSING_USER;
                } else {
                    $miss[] = "";
                }
            }
            $numbers[] = [];
            $texts[] = $col;
        }
        $missing[] = $miss;
    }
    def fmt as string init "sav";
    if ($d.zsav) {
        $fmt = "zsav";
    }
    return Dataset{
        format: $fmt,
        version: "",
        name: "",
        label: decodeText($d.label, $cs),
        encoding: $cs,
        rowCount: $rows,
        variables: $vars,
        numbers: $numbers,
        texts: $texts,
        missing: $missing
    };
}

/**
 * One numeric column of the cases in the raw slot layout.
 *
 * @param flat {bytes} the cases
 * @param order {string} `le` or `be`
 * @param at {int} the offset of the value in the first case
 * @param rows {int} the cases
 * @param caseSize {int} the bytes of a case
 * @param name {string} the variable's name, for the message
 * @return {list of float} the values; NaN and infinity are errors
 */
func savFloats(
    flat as bytes,
    order as string,
    at as int,
    rows as int,
    caseSize as int,
    name as string) {
    if ($rows == 0) {
        return [];
    }
    try {
        return binary.readFloats($order, $flat, $at, $rows, 8, $caseSize);
    } catch (e) {
        fail("a value of " + $name + " that is not a finite number");
    }
    return [];
}

/**
 * The variable a long-string record (7.21, 7.22) names at an offset.
 *
 * @param rec {bytes} the record
 * @param order {string} `le` or `be`
 * @param p {int} the offset of the name's length
 * @param cs {string} the character set
 * @param nameAt {map of string to int} the variables by name
 * @param what {string} the record, for the message
 * @return {int} the variable's index
 */
func savLongVar(
    rec as bytes,
    order as string,
    p as int,
    cs as string,
    nameAt as map of string to int,
    what as string) {
    def n as int init savInt($rec, $order, $p, $what);
    if ($n < 1) {
        fail("an empty variable name in the " + $what);
    }
    need($rec, $p + 4, $n, $what);
    def vname as string init decodeText($rec[$p + 4..$p + 4 + $n], $cs);
    if (not maps.has($nameAt, $vname)) {
        fail("the " + $what + " name a variable the file lacks: " + $vname);
    }
    return $nameAt[$vname];
}
