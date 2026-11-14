# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# statfiles - the por topic: SPSS portable .por. Spliced into statfiles.j via include.
#
# A portable file is text in 80-column lines: a 200-byte vanity splash, a
# 256-byte translation table, `SPSSPORT`, then tagged records whose numbers
# are base 30 (`1.F/` is 1.5, `*.` system-missing) and whose strings are a
# length and the bytes. The line ends are dropped first (a short line counts
# as padded with blanks), then the table maps the file's bytes to the
# portable character set.

/**
 * The ASCII code of each position of the portable character set, -1 where
 * it has none (control codes, reserved and non-ASCII graphics).
 */
def const POR_ASCII as list of int init [
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    120,
    121,
    122,
    32,
    46,
    60,
    40,
    43,
    124,
    38,
    91,
    93,
    33,
    36,
    42,
    41,
    59,
    94,
    45,
    47,
    -1,
    44,
    37,
    95,
    62,
    63,
    96,
    58,
    35,
    64,
    39,
    61,
    34,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    126,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    123,
    125,
    92,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1
];

/** The value of each byte as a base-30 digit: 0 to 29, -2 for `.`, -1 for any other. */
def const POR_DIGITS as list of int init [
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -2,
    -1,
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1
];

/** 30 to the powers 0 to 13, each exact as a float. */
def const POR_POWERS as list of float init [
    1.0,
    30.0,
    900.0,
    27000.0,
    810000.0,
    24300000.0,
    729000000.0,
    21870000000.0,
    656100000000.0,
    19683000000000.0,
    590490000000000.0,
    17714700000000000.0,
    531441000000000000.0,
    15943230000000000000.0
];

/** The same powers as integers. */
def const POR_INT_POWERS as list of int init [
    1,
    30,
    900,
    27000,
    810000,
    24300000,
    729000000,
    21870000000,
    656100000000,
    19683000000000,
    590490000000000,
    17714700000000000,
    531441000000000000
];

/** 2^53: an integer mantissa below it is exact as a float. */
def const POR_EXACT as int init 9007199254740992;

/** The largest integer mantissa kept as an `int`: one more digit could overflow. */
def const POR_WHOLE_MAX as int init 300000000000000000;

/** Where the translation table starts, after the vanity splash. */
def const POR_TABLE_AT as int init 200;

/** Where the records start, after the table and `SPSSPORT`. */
def const POR_RECORDS_AT as int init 464;

/** The most digits a base-30 number may have. */
def const POR_MAX_DIGITS as int init 64;

/**
 * Where a reader stands in the record stream, with what it read last.
 *
 * @field pos {int} the next byte
 * @field num {float} the last number
 * @field sysmis {bool} the last number was system-missing (`*.`)
 */
def struct PorCursor {
    pos as int,
    num as float,
    sysmis as bool
};

/**
 * The file without its line ends, each line padded with blanks to 80
 * columns.
 *
 * @param data {bytes} the file
 * @return {bytes} the character stream
 */
func porStream(data as bytes) {
    def parts as list of bytes init [];
    def lines as list of bytes init binary.split($data, binary.make(1, 10));
    def last as int init len($lines) - 1;
    for (def k in 0..len($lines)) {
        def size as int init len($lines[$k]);
        if ($size > 0 and $lines[$k][$size - 1] == 13) {
            $size = $size - 1;
        }
        if ($k == $last and $size == 0) {
            continue;
        }
        if ($size > 80) {
            fail(io.sprintf("line %d is longer than 80 columns", $k + 1));
        }
        $parts[] = binary.slice($lines[$k], 0, $size);
        if ($size < 80) {
            $parts[] = binary.make(80 - $size, 32);
        }
    }
    return binary.join($parts);
}

/**
 * The byte each file byte stands for, from the translation table: a byte
 * the table names maps to the ASCII form of its portable character, any
 * other byte stays itself. Where two positions hold the same byte, the
 * lower one wins.
 *
 * @param s {bytes} the character stream, at least through the table
 * @return {list of int} the 256 translations
 */
func porTranslation(s as bytes) {
    def tr as list of int init [];
    def set as list of bool init [];
    for (def b in 0..256) {
        $tr[] = $b;
        $set[] = false;
    }
    for (def i in 64..256) {
        def ch as int init POR_ASCII[$i];
        def b as int init $s[POR_TABLE_AT + $i];
        if ($ch >= 0 and not $set[$b]) {
            $tr[$b] = $ch;
            $set[$b] = true;
        }
    }
    return $tr;
}

/**
 * Whether the first bytes are those of this format.
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikePor(data as bytes) {
    def head as bytes init binary.slice($data, 0, math.min(len($data), 600));
    def s as bytes;
    try {
        $s = porStream($head);
    } catch (e) {
        return false;
    }
    if (len($s) < POR_RECORDS_AT) {
        return false;
    }
    def tr as list of int init porTranslation($s);
    def sig as bytes init binary.make(8);
    for (def k in 0..8) {
        $sig[$k] = $tr[$s[456 + $k]];
    }
    return $sig == convert.bytesFromString("utf-8", "SPSSPORT");
}

/**
 * The value of a base-30 digit, -1 for another character.
 *
 * @param c {int} the character
 * @return {int} 0 to 29, or -1
 */
func porDigit(c as int) {
    if ($c >= 48 and $c <= 57) {
        return $c - 48;
    }
    if ($c >= 65 and $c <= 84) {
        return $c - 55;
    }
    return -1;
}

/**
 * Move past blanks.
 *
 * @param s {bytes} the stream
 * @param p {int} where to start
 * @return {int} the first byte that is not a blank
 */
func porSkip(s as bytes, p as int) {
    def q as int init $p;
    while ($q < len($s) and $s[$q] == 32) {
        $q = $q + 1;
    }
    return $q;
}

/**
 * Read a number: base-30 digits with an optional sign, fraction and
 * exponent, ended by `/`; or `*.` for system-missing.
 *
 * @param s {bytes} the stream
 * @param c {PorCursor} the cursor
 * @return {PorCursor} the cursor after it, with `num` and `sysmis` set
 */
func porNumber(s as bytes, c as PorCursor) {
    def n as int init len($s);
    def p as int init porSkip($s, $c.pos);
    if ($p >= $n) {
        fail("the file ends inside a number");
    }
    if ($s[$p] == 42) {
        if ($p + 1 >= $n or $s[$p + 1] != 46) {
            fail(io.sprintf("a malformed missing value at offset %d", $p));
        }
        $c.pos = $p + 2;
        $c.num = 0.0;
        $c.sysmis = true;
        return $c;
    }
    def neg as bool init false;
    if ($s[$p] == 45) {
        $neg = true;
        $p = $p + 1;
    }
    def whole as int init 0;
    def extra as int init 0;
    def start as int init $p;
    def dotAt as int init -1;
    while ($p < $n) {
        def v as int init POR_DIGITS[$s[$p]];
        if ($v >= 0) {
            if ($whole < POR_WHOLE_MAX) {
                $whole = $whole * 30 + $v;
            } else {
                $extra = $extra + 1;
            }
        } elseif ($v == -2 and $dotAt < 0) {
            $dotAt = $p;
        } else {
            break;
        }
        $p = $p + 1;
    }
    def digits as int init $p - $start;
    def mantEnd as int init $p;
    def frac as int init 0;
    if ($dotAt >= 0) {
        $digits = $digits - 1;
        $frac = $p - $dotAt - 1;
    }
    if ($digits == 0 or $digits > POR_MAX_DIGITS) {
        fail(io.sprintf("a malformed number at offset %d", $c.pos));
    }
    def ex as int init 0;
    if ($p < $n and ($s[$p] == 43 or $s[$p] == 45)) {
        def eneg as bool init $s[$p] == 45;
        $p = $p + 1;
        def ed as int init 0;
        while ($p < $n and porDigit($s[$p]) >= 0) {
            $ex = $ex * 30 + porDigit($s[$p]);
            $ed = $ed + 1;
            $p = $p + 1;
            if ($ed > 4) {
                fail(io.sprintf("a malformed number at offset %d", $c.pos));
            }
        }
        if ($ed == 0) {
            fail(io.sprintf("a malformed number at offset %d", $c.pos));
        }
        if ($eneg) {
            $ex = -$ex;
        }
    }
    if ($p >= $n or $s[$p] != 47) {
        fail(io.sprintf("a malformed number at offset %d", $c.pos));
    }
    $c.pos = $p + 1;
    $c.sysmis = false;
    def k as int init $ex - $frac;
    def mant as float init convert.toFloat($whole);
    if ($extra > 0) {
        # only the order of magnitude matters for a mantissa this long
        $mant = $mant * math.pow(30.0, $extra);
        $whole = -1;
    }
    def x as float init $mant;
    if ($mant > 0.0) {
        def lg as float init math.log10($mant) + convert.toFloat($k) * 1.4771212547196624;
        if ($lg > 308.25472) {
            fail(io.sprintf("a number out of range at offset %d", $p));
        }
        if ($lg < -330.0) {
            $x = 0.0;
        } elseif ($whole >= 0 and $whole < POR_EXACT and $k >= 0 and $k < len(POR_POWERS)) {
            # one correctly rounded operation on two exact floats
            $x = $mant * POR_POWERS[$k];
        } elseif ($whole >= 0 and $whole < POR_EXACT and $k < 0 and -$k < len(POR_POWERS)) {
            $x = $mant / POR_POWERS[-$k];
        } elseif ($whole >= 0 and $k < 0 and -$k < len(POR_INT_POWERS)) {
            # exact in decimal, then rounded once; places for 20 guard digits
            $x = decimal.toFloat(decimal.div(
                $whole,
                POR_INT_POWERS[-$k],
                math.max(0, math.ceil(-$lg)) + 40));
        } elseif ($whole >= 0 and $k >= 0 and $k < len(POR_INT_POWERS)) {
            $x = decimal.toFloat(decimal.mul($whole, POR_INT_POWERS[$k]));
        } else {
            $x = porExact($s, $start, $mantEnd, $k, $lg, $whole);
        }
    }
    if ($neg) {
        $x = -$x;
    }
    $c.num = $x;
    return $c;
}

/**
 * The nearest float to a base-30 mantissa times 30^k, computed exactly in
 * `decimal` (for mantissas of 2^53 and over, and large powers).
 *
 * @param s {bytes} the stream
 * @param start {int} the first digit of the mantissa
 * @param end {int} the byte after its last digit
 * @param k {int} the power of 30, the point already taken into account
 * @param lg {float} the decimal logarithm of the value, roughly
 * @param whole {int} the mantissa as an integer, -1 when it does not fit one
 * @return {float} the magnitude; `HIGHEST` for one just past the float range
 */
func porExact(s as bytes, start as int, end as int, k as int, lg as float, whole as int) {
    def m as decimal.Decimal init decimal.from($whole);
    def digits as int init 13;
    if ($whole < 0) {
        $m = decimal.from(0);
        def chunk as int init 0;
        def scale as int init 1;
        $digits = 0;
        for (def q in $start..$end) {
            def v as int init POR_DIGITS[$s[$q]];
            if ($v < 0) {
                continue;
            }
            $chunk = $chunk * 30 + $v;
            $scale = $scale * 30;
            $digits = $digits + 1;
            if ($scale > POR_WHOLE_MAX) {
                $m = decimal.add(decimal.mul($m, $scale), $chunk);
                $chunk = 0;
                $scale = 1;
            }
        }
        $m = decimal.add(decimal.mul($m, $scale), $chunk);
    }
    def power as decimal.Decimal;
    if (math.abs($k) < len(POR_INT_POWERS)) {
        $power = decimal.from(POR_INT_POWERS[math.abs($k)]);
    } else {
        $power = decimal.pow(30, math.abs($k));
    }
    def exact as decimal.Decimal;
    if ($k >= 0) {
        $exact = decimal.mul($m, $power);
    } else {
        # enough places for every significant digit and 20 guard digits
        def places as int init math.max(0, math.ceil(-$lg)) + 2 * $digits + 20;
        $exact = decimal.div($m, $power, $places);
    }
    def x as float init HIGHEST;
    try {
        $x = decimal.toFloat($exact);
    } catch (e) {
        # only a value just past the largest float (PSPP's HIGHEST) gets here
        $x = HIGHEST;
    }
    return $x;
}

/**
 * Read a whole number that is not system-missing.
 *
 * @param s {bytes} the stream
 * @param c {PorCursor} the cursor
 * @param what {string} what it is, for the message
 * @return {PorCursor} the cursor after it, with `num` set
 */
func porInt(s as bytes, c as PorCursor, what as string) {
    def at as int init $c.pos;
    $c = porNumber($s, $c);
    if ($c.sysmis or $c.num < 0.0 or $c.num > 2147483647.0 or
        $c.num != convert.toFloat(math.floor($c.num))) {
        fail(io.sprintf("a malformed %s at offset %d", $what, $at));
    }
    return $c;
}

/**
 * Move past a string: its length, then that many bytes. `porLast` returns
 * the bytes.
 *
 * @param s {bytes} the stream
 * @param c {PorCursor} the cursor
 * @return {PorCursor} the cursor after it, with `num` its length
 */
func porString(s as bytes, c as PorCursor) {
    $c = porInt($s, $c, "string length");
    def n as int init math.floor($c.num);
    need($s, $c.pos, $n, "a string");
    $c.pos = $c.pos + $n;
    return $c;
}

/**
 * The bytes of the string `porString` just moved past.
 *
 * @param s {bytes} the stream
 * @param c {PorCursor} the cursor `porString` returned
 * @return {bytes} the string
 */
func porLast(s as bytes, c as PorCursor) {
    return binary.slice($s, $c.pos - math.floor($c.num), $c.pos);
}

/**
 * Read a SPSS portable .por file.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it
 * @return {Dataset} its contents
 * @throws {Error} kind `"statfiles"` for a malformed file, `"limit"` over a cap
 */
export func readPor(data as bytes, opts as Options) {
    checkSize($opts, 0, 0);
    def s as bytes init porStream($data);
    need($s, 0, POR_RECORDS_AT, "the header");
    def tr as list of int init porTranslation($s);
    def same as bool init true;
    for (def b in 0..256) {
        if ($tr[$b] != $b) {
            $same = false;
            break;
        }
    }
    if (not $same) {
        def out as bytes init binary.slice($s, 0, POR_TABLE_AT + 256);
        for (def k in POR_TABLE_AT + 256..len($s)) {
            $out[] = $tr[$s[$k]];
        }
        $s = $out;
    }
    if (binary.slice($s, 456, POR_RECORDS_AT) != convert.bytesFromString("utf-8", "SPSSPORT")) {
        fail("not an SPSS portable file");
    }
    def cs as string init "utf-8";
    if ($opts.encoding != "") {
        $cs = charsetName($opts.encoding);
    } else {
        try {
            convert.stringFromBytes("utf-8", binary.slice($s, POR_RECORDS_AT, len($s)));
        } catch (e) {
            $cs = "windows-1252";
        }
    }
    def label as string init "";
    if (binary.slice($s, 40, 60) == convert.bytesFromString("utf-8", "ASCII SPSS PORT FILE")) {
        $label = decodeText(binary.slice($s, 60, 80), $cs);
    }
    def c as PorCursor init PorCursor{pos: POR_RECORDS_AT, num: 0.0, sysmis: false};
    need($s, $c.pos, 1, "the version");
    if ($s[$c.pos] != 65) {
        fail("an unknown portable file version");
    }
    $c.pos = $c.pos + 1;
    $c = porString($s, $c);
    $c = porString($s, $c);

    def vars as list of Variable init [];
    def missNum as list of list of float init [];
    def nameAt as map of string to int init {};
    def declared as int init -1;
    def inData as bool init false;
    while (not $inData) {
        $c.pos = porSkip($s, $c.pos);
        need($s, $c.pos, 1, "a record tag");
        def tag as int init $s[$c.pos];
        $c.pos = $c.pos + 1;
        def cur as int init len($vars) - 1;
        match ($tag) {
            when 49, 50, 51, 54 { $c = porString($s, $c); }
            when 52 {
                $c = porInt($s, $c, "variable count");
                $declared = math.floor($c.num);
            }
            when 53 { $c = porInt($s, $c, "precision"); }
            when 55 {
                $c = porInt($s, $c, "variable width");
                def w as int init math.floor($c.num);
                if ($w > 255) {
                    fail(io.sprintf("a string width %d", $w));
                }
                $c = porString($s, $c);
                def vname as string init decodeText(porLast($s, $c), $cs);
                def fmt as list of int init [];
                for (def k in 0..6) {
                    $c = porInt($s, $c, "display format");
                    $fmt[] = math.floor($c.num);
                }
                def v as Variable init Variable{
                    name: $vname,
                    label: "",
                    type: "numeric",
                    storage: "numeric",
                    width: 0,
                    format: savFormatOf($fmt[0], $fmt[1], $fmt[2]),
                    valueLabels: {},
                    missingValues: [],
                    missingRange: []
                };
                if ($w > 0) {
                    $v.type = "string";
                    $v.storage = "string";
                    $v.width = $w;
                }
                if ($vname == "" or maps.has($nameAt, $vname)) {
                    fail("an empty or repeated variable name " + $vname);
                }
                $nameAt[$vname] = len($vars);
                $vars[] = $v;
                $missNum[] = [];
            }
            when 56 {
                porNeedVar($cur);
                if ($vars[$cur].type == "string") {
                    $c = porString($s, $c);
                    $vars[$cur].missingValues[] = decodeText(porLast($s, $c), $cs);
                } else {
                    $c = porValue($s, $c);
                    $vars[$cur].missingValues[] = valueKey($c.num);
                    $missNum[$cur][] = $c.num;
                }
            }
            when 57, 65, 66 {
                porNeedVar($cur);
                if ($vars[$cur].type == "string" or len($vars[$cur].missingRange) > 0) {
                    fail("a missing range on a string, or a second one");
                }
                $c = porValue($s, $c);
                def lo as float init $c.num;
                def hi as float init HIGHEST;
                if ($tag == 57) {
                    $lo = LOWEST;
                    $hi = $c.num;
                } elseif ($tag == 66) {
                    $c = porValue($s, $c);
                    $hi = $c.num;
                }
                $vars[$cur].missingRange = [$lo, $hi];
            }
            when 67 {
                porNeedVar($cur);
                $c = porString($s, $c);
                $vars[$cur].label = decodeText(porLast($s, $c), $cs);
            }
            when 68 {
                $c = porInt($s, $c, "value-label variable count");
                def targets as list of int init [];
                for (def k in 0..math.floor($c.num)) {
                    $c = porString($s, $c);
                    def vname as string init decodeText(porLast($s, $c), $cs);
                    if (not maps.has($nameAt, $vname)) {
                        fail("value labels for a variable the file lacks: " + $vname);
                    }
                    $targets[] = $nameAt[$vname];
                }
                if (len($targets) == 0) {
                    fail("value labels for no variable");
                }
                def textual as bool init $vars[$targets[0]].type == "string";
                for (def vi in $targets) {
                    if (($vars[$vi].type == "string") != $textual) {
                        fail("value labels shared by numeric and string variables");
                    }
                }
                $c = porInt($s, $c, "value-label count");
                for (def k in 0..math.floor($c.num)) {
                    def key as string;
                    if ($textual) {
                        $c = porString($s, $c);
                        $key = decodeText(porLast($s, $c), $cs);
                    } else {
                        $c = porValue($s, $c);
                        $key = valueKey($c.num);
                    }
                    $c = porString($s, $c);
                    def lab as string init decodeText(porLast($s, $c), $cs);
                    for (def vi in $targets) {
                        $vars[$vi].valueLabels[$key] = $lab;
                    }
                }
            }
            when 69 {
                $c = porInt($s, $c, "document line count");
                for (def k in 0..math.floor($c.num)) {
                    $c = porString($s, $c);
                }
            }
            when 70 { $inData = true; }
            else { fail(io.sprintf("an unknown record tag at offset %d", $c.pos - 1)); }
        }
    }
    def nvars as int init len($vars);
    if ($nvars == 0 or $declared != $nvars) {
        fail(io.sprintf("%d variables where the file declares %d", $nvars, $declared));
    }
    def maxRows as int init $opts.maxCells // $nvars;
    def numbers as list of list of float init [];
    def texts as list of list of string init [];
    def missing as list of list of string init [];
    def isText as list of bool init [];
    for (def v in $vars) {
        $numbers[] = [];
        $texts[] = [];
        $missing[] = [];
        $isText[] = $v.type == "string";
    }
    def rows as int init 0;
    while (true) {
        $c.pos = porSkip($s, $c.pos);
        if ($c.pos >= len($s)) {
            fail("the data ends without its end marker");
        }
        if ($s[$c.pos] == 90) {
            break;
        }
        if ($rows == $maxRows) {
            failLimit(io.sprintf("over %d cells", $opts.maxCells));
        }
        for (def i in 0..$nvars) {
            if ($isText[$i]) {
                $c = porString($s, $c);
                if (math.floor($c.num) > $vars[$i].width) {
                    fail(io.sprintf("a value of %s longer than its width", $vars[$i].name));
                }
                $texts[$i][] = decodeText(porLast($s, $c), $cs);
            } else {
                $c = porNumber($s, $c);
                $numbers[$i][] = $c.num;
                if ($c.sysmis) {
                    $missing[$i][] = MISSING_SYSTEM;
                } else {
                    $missing[$i][] = "";
                }
            }
        }
        $rows = $rows + 1;
    }
    for (def k in $c.pos..len($s)) {
        if ($s[$k] != 90 and $s[$k] != 32) {
            fail("data after the end marker");
        }
    }
    for (def i in 0..$nvars) {
        def keys as list of string init $vars[$i].missingValues;
        def rng as list of float init $vars[$i].missingRange;
        if (len($keys) == 0 and len($rng) == 0) {
            if ($isText[$i]) {
                for (def row in 0..$rows) {
                    $missing[$i][] = "";
                }
            }
            continue;
        }
        if ($isText[$i]) {
            for (def row in 0..$rows) {
                if (lists.contains($keys, $texts[$i][$row])) {
                    $missing[$i][] = MISSING_USER;
                } else {
                    $missing[$i][] = "";
                }
            }
            continue;
        }
        def user as list of float init $missNum[$i];
        for (def row in 0..$rows) {
            def x as float init $numbers[$i][$row];
            if ($missing[$i][$row] == "" and
                (lists.contains($user, $x) or len($rng) > 0 and $x >= $rng[0] and $x <= $rng[1])) {
                $missing[$i][$row] = MISSING_USER;
            }
        }
    }
    return Dataset{
        format: "por",
        version: "",
        name: "",
        label: $label,
        encoding: $cs,
        rowCount: $rows,
        variables: $vars,
        numbers: $numbers,
        texts: $texts,
        missing: $missing
    };
}

/**
 * Throw unless a variable record precedes a variable's own record.
 *
 * @param cur {int} the index of the last variable, -1 if none
 */
func porNeedVar(cur as int) {
    if ($cur < 0) {
        fail("a variable's record before any variable");
    }
}

/**
 * Read a number that is a value of a variable, not system-missing.
 *
 * @param s {bytes} the stream
 * @param c {PorCursor} the cursor
 * @return {PorCursor} the cursor after it, with `num` set
 */
func porValue(s as bytes, c as PorCursor) {
    def at as int init $c.pos;
    $c = porNumber($s, $c);
    if ($c.sysmis) {
        fail(io.sprintf("a system-missing value where a value is needed at offset %d", $at));
    }
    return $c;
}
