# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# statfiles - the sas7bdat topic: SAS data sets (.sas7bdat). SAS does not
# document the format; this follows the reverse engineering of ReadStat
# (MIT), parso (Apache-2.0), pandas (BSD-3) and Matthew Shotwell's notes
# for the sas7bdat R package. Spliced into statfiles.j via include.
#
# A file is a header (1024 bytes or more) and a run of equal pages. The
# header gives the alignment (32- or 64-bit), the byte order, the character
# set, the dataset name and the SAS release. A page starts with a page
# header (24 or 40 bytes) holding its type, a row count and a count of
# subheader pointers; the pointers (12 or 24 bytes: offset, length,
# compression code, data flag) follow. Meta pages hold subheaders: row size,
# column size, column text (the text every name, label and format points
# into), column names, column attributes, format and label, and in a
# compressed file every row as its own subheader. Data pages hold rows
# back to back; a mix page holds both. AMD pages carry amended metadata.
#
# The cells are first gathered into one buffer of whole rows, then each
# column is read out of it in bulk with a stride.

# The first 32 bytes of a data set, of a data set written by some other
# programs, and of a format catalog.
def const SAS7_MAGIC as string init "000000000000000000000000c2ea8160b31411cfbd92080009c7318c181f1011";
def const SAS7_MAGIC_ALT as string init "00000000000000000000000000000000000000000000000000000000181f1011";
def const SAS7_MAGIC_CATALOG as string init "000000000000000000000000c2ea8163b31411cfbd92080009c7318c181f1011";

# The character set of a file whose header names none (code 0, or 204 "any").
def const SAS7_DEFAULT_CHARSET as string init "windows-1252";

# The character set codes of the header (byte 70) and their names, from
# ReadStat's table. charsetName maps a name to an `encoding` codec, or
# refuses one the library lacks.
def const SAS7_CHARSET_CODES as list of int init [
    20,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
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
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    75,
    76,
    118,
    119,
    123,
    125,
    126,
    128,
    134,
    136,
    137,
    138,
    140,
    141,
    142,
    163,
    167,
    168,
    169,
    172,
    205,
    227,
    242,
    245,
    246,
    247,
    248
];
def const SAS7_CHARSET_NAMES as list of string init [
    "utf-8",
    "us-ascii",
    "iso-8859-1",
    "iso-8859-2",
    "iso-8859-3",
    "iso-8859-4",
    "iso-8859-5",
    "iso-8859-6",
    "iso-8859-7",
    "iso-8859-8",
    "iso-8859-9",
    "iso-8859-10",
    "iso-8859-11",
    "iso-8859-15",
    "cp437",
    "cp850",
    "cp852",
    "cp857",
    "cp858",
    "cp862",
    "cp864",
    "cp865",
    "cp866",
    "cp869",
    "cp874",
    "cp921",
    "cp922",
    "cp1129",
    "cp720",
    "cp737",
    "cp775",
    "cp860",
    "cp863",
    "windows-1250",
    "windows-1251",
    "windows-1252",
    "windows-1253",
    "windows-1254",
    "windows-1255",
    "windows-1256",
    "windows-1257",
    "windows-1258",
    "macroman",
    "macarabic",
    "machebrew",
    "macgreek",
    "macthai",
    "macturkish",
    "macukraine",
    "cp950",
    "euc-tw",
    "big5",
    "gb18030",
    "windows-936",
    "cp1381",
    "euc-jp",
    "cp932",
    "cp942",
    "shift-jis",
    "euc-kr",
    "cp949",
    "cp949",
    "maciceland",
    "iso-2022-jp",
    "iso-2022-kr",
    "iso-2022-cn",
    "iso-2022-cn-ext",
    "gb18030",
    "iso-8859-14",
    "iso-8859-13",
    "maccroatian",
    "maccyrillic",
    "macromania",
    "shift-jisx0213"
];

# Page types (the low byte's high nibble, masked by SAS7_PAGE_MASK), the flag
# of a page with deleted rows, and the bits of pages that hold no rows or
# metadata (index and compression pages).
def const SAS7_PAGE_MASK as int init 0x0F00;
def const SAS7_PAGE_DATA as int init 0x0100;
def const SAS7_PAGE_MIX as int init 0x0200;
def const SAS7_PAGE_DELETED as int init 0x0080;
def const SAS7_PAGE_SKIP as int init 0x9000;

# The subheader kinds, from their signatures.
def const SAS7_SH_DATA as int init 0;
def const SAS7_SH_ROW_SIZE as int init 1;
def const SAS7_SH_COLUMN_SIZE as int init 2;
def const SAS7_SH_COUNTS as int init 3;
def const SAS7_SH_FORMAT as int init 4;
def const SAS7_SH_ATTRS as int init 5;
def const SAS7_SH_TEXT as int init 6;
def const SAS7_SH_LIST as int init 7;
def const SAS7_SH_NAME as int init 8;
def const SAS7_SH_UNKNOWN as int init 9;

# The compression codes of a subheader pointer: a plain subheader or row, a
# truncated (empty) one, a row moved to another page and the reference to
# it, a compressed row, a deleted row, and moved rows no reference points at.
def const SAS7_COMP_NONE as int init 0;
def const SAS7_COMP_TRUNC as int init 1;
def const SAS7_COMP_NONE_MOVED as int init 2;
def const SAS7_COMP_REFERENCE as int init 3;
def const SAS7_COMP_ROW as int init 4;
def const SAS7_COMP_DELETED as int init 5;
def const SAS7_COMP_ROW_MOVED as int init 6;
def const SAS7_COMP_NONE_UNREFERENCED as int init 9;
def const SAS7_COMP_ROW_UNREFERENCED as int init 13;

# The farthest back an RDC copy reaches (3 + 15 + 255 * 16).
def const SAS7_RDC_WINDOW as int init 4098;

# The missing code of a NaN whose tag byte is stored as 0 until it is told
# apart from an infinity.
def const SAS7_MAYBE_INFINITE as string init "?";

# The leading zero bits of a 4-bit value.
def const SAS7_CLZ4 as list of int init [4, 3, 2, 2, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0];

# The most bytes the header and a page may have, and the most pages.
def const SAS7_MAX_SIZE as int init 16777216;

/*
 * What the file header says.
 */
def struct Sas7Head {
    u64 as bool,
    order as string,
    align as int,
    headerSize as int,
    pageSize as int,
    pageCount as int,
    pageHead as int,
    pointerSize as int,
    word as int,
    release as string,
    statTransfer as bool,
    name as bytes,
    charset as string
};

/*
 * Every page and every subheader pointer of the pages that have them, as
 * parallel lists. A pointer's offset is absolute; `ptrKinds` is the
 * subheader kind for codes 0 and 2, -1 otherwise.
 */
def struct Sas7Pages {
    types as list of int,
    firstPointer as list of int,
    pointerCount as list of int,
    rowStart as list of int,
    blockCount as list of int,
    ptrOffsets as list of int,
    ptrLengths as list of int,
    ptrComps as list of int,
    ptrFlags as list of int,
    ptrKinds as list of int
};

/*
 * The metadata subheaders, gathered. A text reference is three entries of
 * a flat list: the text subheader, the offset in it and the length.
 */
def struct Sas7Meta {
    texts as list of bytes,
    rowSizeSeen as bool,
    rowLength as int,
    totalRows as int,
    deletedRows as int,
    mixRows as int,
    labelRef as list of int,
    compressionRef as list of int,
    columnCount as int,
    nameRefs as list of int,
    offsets as list of int,
    widths as list of int,
    numeric as list of bool,
    formatWidths as list of int,
    formatDigits as list of int,
    formatRefs as list of int,
    labelRefs as list of int
};

/* One numeric column. */
def struct Sas7Column {
    numbers as list of float,
    missing as list of string
};

/*
 * The NaNs of the numeric columns marked (sas7Marks): the marked rows, and
 * per byte of a row the column whose top bytes start there, -1 for none.
 */
def struct Sas7Marks {
    marked as bytes,
    owner as list of int
};

/**
 * Whether the first bytes are those of a SAS data set.
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikeSas7bdat(data as bytes) {
    if (len($data) < 32) {
        return false;
    }
    def magic as bytes init $data[..32];
    return $magic == encoding.fromText("hex", SAS7_MAGIC) or
        $magic == encoding.fromText("hex", SAS7_MAGIC_ALT);
}

/**
 * Whether the first bytes are those of a SAS format catalog.
 *
 * @param data {bytes} the file
 * @return {bool} true when it is
 */
func looksLikeSas7bcat(data as bytes) {
    return len($data) >= 32 and
        $data[..32] == encoding.fromText("hex", SAS7_MAGIC_CATALOG);
}

/**
 * Read a SAS data set (`.sas7bdat`): 32- or 64-bit, either byte order,
 * uncompressed or with rows compressed by RLE (`SASYZCRL`, SAS's
 * `COMPRESS=CHAR`) or RDC (`SASYZCR2`, `COMPRESS=BINARY`).
 *
 * Text is decoded from `Options.encoding`, else from the character set the
 * header names, else windows-1252. A missing number has the code `.`,
 * `.a` to `.z` or `._`. Rows the file marks deleted are left out. Dates
 * and times stay numbers (days or seconds since 1960-01-01) with their
 * format, such as `DATE9.` or `DATETIME20.`. Value labels live in a
 * separate catalog: `readSas7bcat` and `withSasLabels` attach them.
 *
 * @param data {bytes} the file
 * @param opts {Options} how to read it; `maxBytes` caps the unpacked rows
 *   of a compressed file
 * @return {Dataset} its contents; `format` is `sas7bdat`, `version` the
 *   SAS release that wrote it (such as `9.0401M5`), `name` the data set's
 *   name
 * @throws {Error} kind `"statfiles"` for a malformed file, `"limit"` over
 *   `Options.maxCells` or `Options.maxBytes`
 * @example
 *   def ds as statfiles.Dataset init statfiles.readSas7bdat(fs.readBytes("cars.sas7bdat"), statfiles.options());
 */
export func readSas7bdat(data as bytes, opts as Options) {
    if (looksLikeSas7bcat($data)) {
        fail("a SAS format catalog, not a data set: readSas7bcat reads it");
    }
    if (not looksLikeSas7bdat($data)) {
        fail("not a SAS data set (no sas7bdat signature)");
    }
    def head as Sas7Head init sas7Head($data, $opts);
    def pages as Sas7Pages init sas7Pages($data, $head);
    def meta as Sas7Meta init sas7Meta($data, $head, $pages);
    def count as int init $meta.columnCount;
    def live as int init $meta.totalRows - $meta.deletedRows;
    checkSize($opts, $live, $count);
    def compression as string init sas7Compression($meta, $head.charset);
    if ($compression != "" and $meta.rowLength > 0 and $live > $opts.maxBytes // $meta.rowLength) {
        failLimit(io.sprintf(
            "%d compressed rows of %d bytes unpack to over %d bytes",
            $live,
            $meta.rowLength,
            $opts.maxBytes));
    }
    def variables as list of Variable init sas7Variables($meta, $head.charset);
    def flat as bytes init sas7Rows($data, $head, $pages, $meta, $compression);
    return sas7Decode($flat, $head, $meta, $variables, $live);
}

/**
 * Read and check the file header.
 *
 * @param data {bytes} the file, whose signature has been checked
 * @param opts {Options} the options (their encoding overrides the file's)
 * @return {Sas7Head} the header
 */
func sas7Head(data as bytes, opts as Options) {
    checkSize($opts, 0, 0);
    need($data, 0, 288, "the file header");
    def u64 as bool init $data[32] == 0x33;
    def align as int init 0;
    if ($data[35] == 0x33) {
        $align = 4;
    }
    def order as string init "le";
    if ($data[37] == 0) {
        $order = "be";
    } elseif ($data[37] != 1) {
        fail(io.sprintf("the byte order mark is %d, not 0 or 1", $data[37]));
    }
    def headerSize as int init binary.readUint($order, $data, 196 + $align, 4);
    def pageSize as int init binary.readUint($order, $data, 200 + $align, 4);
    if ($headerSize < 1024 or $headerSize > SAS7_MAX_SIZE or $pageSize < 1024 or
        $pageSize > SAS7_MAX_SIZE) {
        fail(io.sprintf("a header of %d bytes and pages of %d bytes", $headerSize, $pageSize));
    }
    def pageCount as int init 0;
    def at as int init 216 + $align;
    if ($u64) {
        $pageCount = binary.readInt($order, $data, 204 + $align, 8);
        $at = $at + 4;
    } else {
        $pageCount = binary.readUint($order, $data, 204 + $align, 4);
    }
    if ($pageCount < 0 or $pageCount > SAS7_MAX_SIZE) {
        fail(io.sprintf("a page count of %d", $pageCount));
    }
    def size as int init $headerSize + $pageCount * $pageSize;
    if (len($data) != $size) {
        fail(io.sprintf(
            "the file is %d bytes, its header declares %d (%d pages of %d bytes); truncated?",
            len($data),
            $size,
            $pageCount,
            $pageSize));
    }
    def release as string init encoding.decode("iso-8859-1", $data[$at..$at + 8]);
    def m as regex.Match init regex.find('^([1-9V])\.([0-9]{4})([A-Z])([0-9A-Z])$', $release);
    if ($m.start < 0) {
        fail("the SAS release in the header is not a release (" + strings.trim($release) + ")");
    }
    def major as string init $m.groups[0];
    def tag as string init $m.groups[2];
    def revision as string init $m.groups[3];
    if (($major == "8" or $major == "9") and $tag != "M" and $tag != "J" and $tag != "T") {
        fail("the SAS release in the header is not a release (" + $release + ")");
    }
    if (not ($revision >= "0" and $revision <= "9" or $tag == "T" and $revision == "K")) {
        fail("the SAS release in the header is not a release (" + $release + ")");
    }
    def h as Sas7Head init Sas7Head{
        u64: $u64,
        order: $order,
        align: $align,
        headerSize: $headerSize,
        pageSize: $pageSize,
        pageCount: $pageCount,
        pageHead: 24,
        pointerSize: 12,
        word: 4,
        release: $release,
        statTransfer: ($major == "8" or $major == "9") and $m.groups[1] == "0000" and
            ($revision == "0" or $revision == "K"),
        name: $data[92..124],
        charset: ""
    };
    if ($u64) {
        $h.pageHead = 40;
        $h.pointerSize = 24;
        $h.word = 8;
    }
    if ($opts.encoding != "") {
        $h.charset = charsetName($opts.encoding);
    } else {
        $h.charset = sas7Charset($data[70]);
    }
    return $h;
}

/**
 * The `encoding` codec of a header's character set code.
 *
 * @param code {int} the code (header byte 70)
 * @return {string} the codec name, or `utf-8`
 */
func sas7Charset(code as int) {
    if ($code == 0 or $code == 204) {
        return SAS7_DEFAULT_CHARSET;
    }
    def i as int init lists.indexOf(SAS7_CHARSET_CODES, $code);
    if ($i < 0) {
        fail(io.sprintf("the character set code %d is unknown (set Options.encoding)", $code));
    }
    return charsetName(SAS7_CHARSET_NAMES[$i]);
}

/**
 * A pointer-sized field: 8 bytes in a 64-bit file, else 4.
 *
 * @param data {bytes} the file
 * @param at {int} the field's offset, inside the file
 * @param head {Sas7Head} the header
 * @return {int} the value; a 64-bit value with its top bit set is negative
 */
func sas7Word(data as bytes, at as int, head as Sas7Head) {
    if ($head.u64) {
        return binary.readInt($head.order, $data, $at, 8);
    }
    return binary.readUint($head.order, $data, $at, 4);
}

/**
 * Walk the pages: note each page's type and row area, and read and check
 * the subheader pointers of the pages that have them.
 *
 * @param data {bytes} the file
 * @param head {Sas7Head} the header
 * @return {Sas7Pages} the pages and pointers
 */
func sas7Pages(data as bytes, head as Sas7Head) {
    def p as Sas7Pages init Sas7Pages{
        types: [],
        firstPointer: [],
        pointerCount: [],
        rowStart: [],
        blockCount: [],
        ptrOffsets: [],
        ptrLengths: [],
        ptrComps: [],
        ptrFlags: [],
        ptrKinds: []
    };
    def ps as int init $head.pageSize;
    def ph as int init $head.pageHead;
    for (def page in 0..$head.pageCount) {
        def base as int init $head.headerSize + $page * $ps;
        def t as int init binary.readUint($head.order, $data, $base + $ph - 8, 2);
        def count as int init binary.readUint($head.order, $data, $base + $ph - 4, 2);
        $p.types[] = $t;
        $p.firstPointer[] = len($p.ptrOffsets);
        $p.blockCount[] = binary.readUint($head.order, $data, $base + $ph - 6, 2);
        if (($t & SAS7_PAGE_MASK) == SAS7_PAGE_DATA) {
            $p.pointerCount[] = 0;
            $p.rowStart[] = $base + $ph;
            continue;
        }
        if (($t & SAS7_PAGE_SKIP) != 0) {
            $p.pointerCount[] = 0;
            $p.rowStart[] = -1;
            continue;
        }
        def end as int init $ph + $count * $head.pointerSize;
        if ($end > $ps) {
            fail(io.sprintf("page %d has %d subheader pointers, more than fit", $page, $count));
        }
        $p.pointerCount[] = $count;
        for (def i in 0..$count) {
            def at as int init $base + $ph + $i * $head.pointerSize;
            def off as int init sas7Word($data, $at, $head);
            def size as int init sas7Word($data, $at + $head.word, $head);
            def comp as int init $data[$at + 2 * $head.word];
            def kind as int init -1;
            if ($size > 0 and $comp != SAS7_COMP_TRUNC and $comp != SAS7_COMP_REFERENCE) {
                if ($off < $end or $size < 0 or $off > $ps or $size > $ps or $off + $size > $ps) {
                    fail(io.sprintf(
                        "subheader %d of page %d lies outside the page (offset %d, length %d)",
                        $i,
                        $page,
                        $off,
                        $size));
                }
                if ($comp == SAS7_COMP_NONE or $comp == SAS7_COMP_NONE_MOVED) {
                    if ($size >= $head.word) {
                        $kind = sas7Kind($data, $base + $off, $head);
                    } elseif ($data[$at + 2 * $head.word + 1] != 0) {
                        # a row too short to hold a signature (ReadStat
                        # stores a row that does not compress as it is)
                        $kind = SAS7_SH_DATA;
                    } else {
                        fail(io.sprintf(
                            "subheader %d of page %d is %d bytes long",
                            $i,
                            $page,
                            $size));
                    }
                }
                $off = $base + $off;
            }
            $p.ptrOffsets[] = $off;
            $p.ptrLengths[] = $size;
            $p.ptrComps[] = $comp;
            $p.ptrFlags[] = $data[$at + 2 * $head.word + 1];
            $p.ptrKinds[] = $kind;
        }
        def rows as int init -1;
        if (($t & SAS7_PAGE_MASK) == SAS7_PAGE_MIX) {
            $rows = $end;
            if ($end % 8 == 4 and $end + 4 <= $ps) {
                def pad as int init binary.readUint("le", $data, $base + $end, 4);
                if ($pad == 0 or $pad == 0x20202020 or not $head.statTransfer) {
                    $rows = $end + 4;
                }
            }
            $rows = $base + $rows;
        }
        $p.rowStart[] = $rows;
    }
    return $p;
}

/**
 * The kind of a subheader, from its signature (the first 4 or 8 bytes).
 *
 * @param data {bytes} the file
 * @param at {int} the subheader's offset
 * @param head {Sas7Head} the header
 * @return {int} a SAS7_SH_* kind
 */
func sas7Kind(data as bytes, at as int, head as Sas7Head) {
    def sig as int init binary.readUint($head.order, $data, $at, 4);
    if ($head.u64 and $head.order == "be") {
        # big-endian 64-bit: row and column size use the first four bytes;
        # the others are 0xFFFFFFFF followed by the 32-bit signature
        if ($sig == 0xF7F7F7F7) {
            return SAS7_SH_ROW_SIZE;
        }
        if ($sig == 0xF6F6F6F6) {
            return SAS7_SH_COLUMN_SIZE;
        }
        if ($sig != 0xFFFFFFFF) {
            return SAS7_SH_DATA;
        }
        return sas7Kind32(binary.readUint("be", $data, $at + 4, 4));
    }
    if ($head.u64) {
        def high as int init binary.readUint("le", $data, $at + 4, 4);
        if ($high == 0 and ($sig == 0xF7F7F7F7 or $sig == 0xF6F6F6F6)) {
            return sas7Kind32($sig);
        }
        if ($high != 0xFFFFFFFF) {
            return SAS7_SH_DATA;
        }
    }
    return sas7Kind32($sig);
}

/**
 * The kind of a subheader from a 32-bit signature.
 *
 * @param sig {int} the signature
 * @return {int} a SAS7_SH_* kind
 */
func sas7Kind32(sig as int) {
    if ($sig == 0xF7F7F7F7) {
        return SAS7_SH_ROW_SIZE;
    }
    if ($sig == 0xF6F6F6F6) {
        return SAS7_SH_COLUMN_SIZE;
    }
    if ($sig == 0xFFFFFC00) {
        return SAS7_SH_COUNTS;
    }
    if ($sig == 0xFFFFFBFE) {
        return SAS7_SH_FORMAT;
    }
    if ($sig == 0xFFFFFFFC) {
        return SAS7_SH_ATTRS;
    }
    if ($sig == 0xFFFFFFFD) {
        return SAS7_SH_TEXT;
    }
    if ($sig == 0xFFFFFFFE) {
        return SAS7_SH_LIST;
    }
    if ($sig == 0xFFFFFFFF) {
        return SAS7_SH_NAME;
    }
    if (($sig & 0xFFFFFFF8) == 0xFFFFFFF8) {
        return SAS7_SH_UNKNOWN;
    }
    return SAS7_SH_DATA;
}

/**
 * Gather the metadata subheaders, in file order: first every column text
 * subheader (the others point into them), then the rest.
 *
 * @param data {bytes} the file
 * @param head {Sas7Head} the header
 * @param pages {Sas7Pages} the pages
 * @return {Sas7Meta} the metadata, checked for consistency
 */
func sas7Meta(data as bytes, head as Sas7Head, pages as Sas7Pages) {
    def m as Sas7Meta init Sas7Meta{
        texts: [],
        rowSizeSeen: false,
        rowLength: 0,
        totalRows: 0,
        deletedRows: 0,
        mixRows: 0,
        labelRef: [0, 0, 0],
        compressionRef: [0, 0, 0],
        columnCount: -1,
        nameRefs: [],
        offsets: [],
        widths: [],
        numeric: [],
        formatWidths: [],
        formatDigits: [],
        formatRefs: [],
        labelRefs: []
    };
    def sig as int init $head.word;
    for (def i in 0..len($pages.ptrKinds)) {
        if ($pages.ptrComps[$i] == SAS7_COMP_NONE and $pages.ptrKinds[$i] == SAS7_SH_TEXT) {
            def at as int init $pages.ptrOffsets[$i];
            def size as int init $pages.ptrLengths[$i];
            sas7Remainder($data, $at, $size, $head, "column text");
            $m.texts[] = $data[$at + $sig..$at + $size];
        }
    }
    for (def i in 0..len($pages.ptrKinds)) {
        def kind as int init $pages.ptrKinds[$i];
        if ($pages.ptrComps[$i] != SAS7_COMP_NONE or $kind < 0 or $kind == SAS7_SH_TEXT) {
            continue;
        }
        def at as int init $pages.ptrOffsets[$i];
        def size as int init $pages.ptrLengths[$i];
        if ($kind == SAS7_SH_DATA) {
            if ($pages.ptrFlags[$i] == 0) {
                fail(io.sprintf("a subheader with the unknown signature at offset %d", $at));
            }
        } elseif ($kind == SAS7_SH_ROW_SIZE) {
            $m = sas7RowSize($data, $at, $size, $head, $m);
        } elseif ($kind == SAS7_SH_COLUMN_SIZE) {
            if ($m.columnCount >= 0) {
                fail("two column size subheaders");
            }
            if ($size < 2 * $sig) {
                fail("a column size subheader too short");
            }
            $m.columnCount = sas7Word($data, $at + $sig, $head);
            if ($m.columnCount < 0 or $m.columnCount > 0xFFFF) {
                fail(io.sprintf("a column count of %d", $m.columnCount));
            }
        } elseif ($kind == SAS7_SH_NAME) {
            sas7Remainder($data, $at, $size, $head, "column name");
            def first as int init $at + $sig + 8;
            def n as int init ($size - 20) // 8;
            if ($head.u64) {
                $n = ($size - 28) // 8;
            }
            for (def k in 0..$n) {
                for (def f in 0..3) {
                    $m.nameRefs[] = binary.readUint(
                        $head.order,
                        $data,
                        $first + 8 * $k + 2 * $f,
                        2);
                }
            }
        } elseif ($kind == SAS7_SH_ATTRS) {
            sas7Remainder($data, $at, $size, $head, "column attributes");
            def step as int init $sig + 8;
            def n as int init ($size - 20) // 12;
            if ($head.u64) {
                $n = ($size - 28) // 16;
            }
            def first as int init $at + $sig + 8;
            for (def k in 0..$n) {
                def e as int init $first + $k * $step;
                def t as int init $data[$e + $sig + 6];
                if ($t != 1 and $t != 2) {
                    fail(io.sprintf(
                        "column %d has type %d, not 1 (numeric) or 2 (character)",
                        len($m.offsets) + 1,
                        $t));
                }
                $m.offsets[] = sas7Word($data, $e, $head);
                $m.widths[] = binary.readUint($head.order, $data, $e + $sig, 4);
                $m.numeric[] = $t == 1;
            }
        } elseif ($kind == SAS7_SH_FORMAT) {
            def base as int init 12;
            if ($head.u64) {
                $base = 24;
            }
            if ($size < $base + 34) {
                fail("a format and label subheader too short");
            }
            $m.formatWidths[] = binary.readUint($head.order, $data, $at + $base, 2);
            $m.formatDigits[] = binary.readUint($head.order, $data, $at + $base + 2, 2);
            for (def f in 0..3) {
                $m.formatRefs[] = binary.readUint($head.order, $data, $at + $base + 22 + 2 * $f, 2);
            }
            for (def f in 0..3) {
                $m.labelRefs[] = binary.readUint($head.order, $data, $at + $base + 28 + 2 * $f, 2);
            }
        }
    }
    if (not $m.rowSizeSeen) {
        fail("no row size subheader");
    }
    if ($m.columnCount < 0) {
        fail("no column size subheader");
    }
    def n as int init $m.columnCount;
    if (len($m.nameRefs) != 3 * $n or len($m.offsets) != $n or len($m.formatWidths) != $n) {
        fail(io.sprintf(
            "%d columns, but %d names, %d attributes and %d formats",
            $n,
            len($m.nameRefs) // 3,
            len($m.offsets),
            len($m.formatWidths)));
    }
    for (def i in 0..$n) {
        def w as int init $m.widths[$i];
        if ($m.numeric[$i] and ($w < 3 or $w > 8)) {
            fail(io.sprintf("numeric column %d is %d bytes long, not 3 to 8", $i + 1, $w));
        }
        if (not $m.numeric[$i] and ($w < 1 or $w > 32767)) {
            fail(io.sprintf("character column %d is %d bytes long", $i + 1, $w));
        }
        if ($m.offsets[$i] < 0 or $m.offsets[$i] > $m.rowLength or $m.offsets[$i] +
            $w > $m.rowLength) {
            fail(io.sprintf(
                "column %d (offset %d, %d bytes) lies outside the %d-byte row",
                $i + 1,
                $m.offsets[$i],
                $w,
                $m.rowLength));
        }
    }
    return $m;
}

/**
 * Throw unless a subheader's remainder field (after the signature) is its
 * length less the signature twice and four bytes.
 *
 * @param data {bytes} the file
 * @param at {int} the subheader's offset
 * @param size {int} its length
 * @param head {Sas7Head} the header
 * @param what {string} the subheader, for the message
 */
func sas7Remainder(data as bytes, at as int, size as int, head as Sas7Head, what as string) {
    if ($size < 20 + 2 * ($head.word - 4)) {
        fail(io.sprintf("a %s subheader whose length does not match (offset %d)", $what, $at));
    }
    def rest as int init binary.readUint($head.order, $data, $at + $head.word, 2);
    if ($rest != $size - 4 - 2 * $head.word) {
        fail(io.sprintf("a %s subheader whose length does not match (offset %d)", $what, $at));
    }
}

/**
 * Read the row size subheader into the metadata.
 *
 * @param data {bytes} the file
 * @param at {int} the subheader's offset
 * @param size {int} its length
 * @param head {Sas7Head} the header
 * @param m {Sas7Meta} the metadata so far
 * @return {Sas7Meta} the metadata with the row size
 */
func sas7RowSize(data as bytes, at as int, size as int, head as Sas7Head, m as Sas7Meta) {
    if ($m.rowSizeSeen) {
        fail("two row size subheaders");
    }
    def w as int init $head.word;
    if ($size < 190 or $head.u64 and $size < 250) {
        fail("a row size subheader too short");
    }
    $m.rowSizeSeen = true;
    $m.rowLength = sas7Word($data, $at + 5 * $w, $head);
    $m.totalRows = sas7Word($data, $at + 6 * $w, $head);
    $m.deletedRows = sas7Word($data, $at + 7 * $w, $head);
    $m.mixRows = sas7Word($data, $at + 15 * $w, $head);
    if ($m.rowLength < 0 or $m.rowLength > $head.pageSize) {
        fail(io.sprintf("a row length of %d with pages of %d bytes", $m.rowLength, $head.pageSize));
    }
    if ($m.totalRows < 0 or $m.deletedRows < 0 or $m.deletedRows > $m.totalRows) {
        fail(io.sprintf("%d rows of which %d deleted", $m.totalRows, $m.deletedRows));
    }
    if ($m.mixRows < 0 or $m.mixRows > $head.pageSize or $m.mixRows * $m.rowLength > $head.pageSize) {
        fail(io.sprintf("%d rows on a mix page do not fit in it", $m.mixRows));
    }
    for (def f in 0..3) {
        $m.labelRef[$f] = binary.readUint($head.order, $data, $at + $size - 130 + 2 * $f, 2);
        $m.compressionRef[$f] = binary.readUint($head.order, $data, $at + $size - 118 + 2 * $f, 2);
    }
    return $m;
}

/**
 * The bytes a text reference points at.
 *
 * @param m {Sas7Meta} the metadata, with the text subheaders
 * @param refs {list of int} flat text references
 * @param i {int} which reference
 * @return {bytes} the text, empty for a reference of length 0
 */
func sas7TextBytes(m as Sas7Meta, refs as list of int, i as int) {
    def idx as int init $refs[3 * $i];
    def off as int init $refs[3 * $i + 1];
    def n as int init $refs[3 * $i + 2];
    if ($n == 0) {
        return binary.make(0);
    }
    if ($idx >= len($m.texts) or $off + $n > len($m.texts[$idx])) {
        fail(io.sprintf("a text reference (%d, %d, %d) outside the column text", $idx, $off, $n));
    }
    return $m.texts[$idx][$off..$off + $n];
}

/**
 * The compression the row size subheader names.
 *
 * @param m {Sas7Meta} the metadata
 * @param charset {string} the character set
 * @return {string} `rle`, `rdc` or `""` for none
 */
func sas7Compression(m as Sas7Meta, charset as string) {
    def name as bytes init sas7TextBytes($m, $m.compressionRef, 0);
    if (len($name) == 0) {
        return "";
    }
    def text as string init decodeText($name, $charset);
    if ($text == "SASYZCRL") {
        return "rle";
    }
    if ($text == "SASYZCR2") {
        return "rdc";
    }
    return "";
}

/**
 * The variables, with their names, labels and formats.
 *
 * @param m {Sas7Meta} the metadata
 * @param charset {string} the character set of the text
 * @return {list of Variable} the variables, in file order
 */
func sas7Variables(m as Sas7Meta, charset as string) {
    def out as list of Variable init [];
    for (def i in 0..$m.columnCount) {
        def v as Variable init Variable{
            name: decodeText(sas7TextBytes($m, $m.nameRefs, $i), $charset),
            label: decodeText(sas7TextBytes($m, $m.labelRefs, $i), $charset),
            type: "string",
            storage: "string",
            width: $m.widths[$i],
            format: sas7Format(
                decodeText(sas7TextBytes($m, $m.formatRefs, $i), $charset),
                $m.formatWidths[$i],
                $m.formatDigits[$i]),
            valueLabels: {},
            missingValues: [],
            missingRange: []
        };
        if ($m.numeric[$i]) {
            $v.type = "numeric";
            $v.storage = "numeric";
        }
        $out[] = $v;
    }
    return $out;
}

/**
 * A display format as SAS writes it: the name, the width and a period,
 * then the decimals (`DATE9.`, `8.2`, `$CHAR20.`). A name that holds a
 * period already, with no width or decimals, is a whole format as older
 * ReadStat writers stored it and is kept.
 *
 * @param name {string} the format's name, `""` for the default
 * @param width {int} its width, 0 if none
 * @param digits {int} its decimals, 0 if none
 * @return {string} the format, `""` when the variable has none
 */
func sas7Format(name as string, width as int, digits as int) {
    if ($width == 0 and $digits != 0) {
        fail(io.sprintf("the format %s has %d decimals but no width", $name, $digits));
    }
    if (strings.contains($name, ".")) {
        if ($width == 0 and $digits == 0) {
            return $name;
        }
        fail("the format name " + $name + " holds a period");
    }
    if ($name == "" and $width == 0) {
        return "";
    }
    def out as string init $name;
    if ($width > 0) {
        $out = $out + convert.toString($width);
    }
    $out = $out + ".";
    if ($digits > 0) {
        $out = $out + convert.toString($digits);
    }
    return $out;
}

/**
 * Gather every row, in file order, into one buffer: the rows of data and
 * mix pages, rows stored in subheaders, compressed rows unpacked, rows
 * moved to another page read where they are referenced, deleted rows left
 * out.
 *
 * @param data {bytes} the file
 * @param head {Sas7Head} the header
 * @param pages {Sas7Pages} the pages
 * @param m {Sas7Meta} the metadata
 * @param compression {string} `rle`, `rdc` or `""`
 * @return {bytes} the live rows, `Sas7Meta.rowLength` bytes each
 */
func sas7Rows(
    data as bytes,
    head as Sas7Head,
    pages as Sas7Pages,
    m as Sas7Meta,
    compression as string) {
    def live as int init $m.totalRows - $m.deletedRows;
    def rl as int init $m.rowLength;
    def parts as list of bytes init [];
    def got as int init 0;
    def deleted as int init 0;
    for (def page in 0..$head.pageCount) {
        def t as int init $pages.types[$page];
        def base as int init $head.headerSize + $page * $head.pageSize;
        def pageEnd as int init $base + $head.pageSize;
        def rows as int init 0;
        if (($t & SAS7_PAGE_MASK) == SAS7_PAGE_DATA) {
            $rows = $pages.blockCount[$page];
        } elseif (($t & SAS7_PAGE_SKIP) != 0) {
            continue;
        } else {
            def first as int init $pages.firstPointer[$page];
            for (def i in $first..$first + $pages.pointerCount[$page]) {
                def comp as int init $pages.ptrComps[$i];
                def size as int init $pages.ptrLengths[$i];
                if ($size <= 0 or $comp == SAS7_COMP_TRUNC) {
                    continue;
                }
                def row as bytes;
                if ($comp == SAS7_COMP_REFERENCE) {
                    $row = sas7Moved(
                        $data,
                        $head,
                        $pages,
                        $pages.ptrOffsets[$i],
                        $size,
                        $rl,
                        $compression);
                } elseif ($comp == SAS7_COMP_NONE) {
                    if ($pages.ptrKinds[$i] != SAS7_SH_DATA or $pages.ptrFlags[$i] == 0) {
                        continue;
                    }
                    if ($size != $rl) {
                        fail(io.sprintf("a row subheader of %d bytes, the rows are %d", $size, $rl));
                    }
                    $row = $data[$pages.ptrOffsets[$i]..$pages.ptrOffsets[$i] + $size];
                } elseif ($comp == SAS7_COMP_ROW) {
                    $row = sas7Unpack($data, $pages.ptrOffsets[$i], $size, $rl, $compression);
                } elseif ($comp == SAS7_COMP_DELETED) {
                    $deleted = $deleted + 1;
                    if ($deleted > $m.deletedRows) {
                        fail(io.sprintf(
                            "more deleted rows than the %d the file declares",
                            $m.deletedRows));
                    }
                    continue;
                } elseif ($comp == SAS7_COMP_NONE_MOVED or $comp == SAS7_COMP_ROW_MOVED or
                    $comp == SAS7_COMP_NONE_UNREFERENCED or $comp == SAS7_COMP_ROW_UNREFERENCED) {
                    continue;
                } else {
                    fail(io.sprintf("a subheader of the unknown compression code %d", $comp));
                }
                if ($got == $live) {
                    fail(io.sprintf("more rows than the %d the file declares", $live));
                }
                $parts[] = $row;
                $got = $got + 1;
            }
            if (($t & SAS7_PAGE_MASK) != SAS7_PAGE_MIX) {
                continue;
            }
            $rows = $m.mixRows;
        }
        if ($rows == 0) {
            continue;
        }
        def start as int init $pages.rowStart[$page];
        if (($t & SAS7_PAGE_DELETED) == 0) {
            def take as int init $rows;
            if (($t & SAS7_PAGE_MASK) == SAS7_PAGE_MIX) {
                $take = math.min($rows, $live - $got);
            } elseif ($got + $rows > $live) {
                fail(io.sprintf("more rows than the %d the file declares", $live));
            }
            if ($start + $take * $rl > $pageEnd) {
                fail(io.sprintf(
                    "page %d holds %d rows of %d bytes, more than fit",
                    $page,
                    $take,
                    $rl));
            }
            if ($take > 0) {
                $parts[] = $data[$start..$start + $take * $rl];
                $got = $got + $take;
            }
            continue;
        }
        # a page with deleted rows: a bitmap after the rows marks them
        def onPage as int init math.min($rows, $m.totalRows);
        def unused as int init sas7Word($data, $base + 3 * $head.word, $head);
        if ($unused < 0 or $unused > $head.pageSize) {
            fail(io.sprintf("the deleted-row marks of page %d lie outside it", $page));
        }
        def bitmap as int init $start + $onPage * $rl + $unused;
        if ($bitmap + ($onPage + 7) // 8 > $pageEnd) {
            fail(io.sprintf("the deleted-row marks of page %d lie outside it", $page));
        }
        for (def r in 0..$rows) {
            if ($got == $live and ($t & SAS7_PAGE_MASK) == SAS7_PAGE_MIX) {
                break;
            }
            if ($start + ($r + 1) * $rl > $pageEnd) {
                fail(io.sprintf(
                    "page %d holds %d rows of %d bytes, more than fit",
                    $page,
                    $rows,
                    $rl));
            }
            if ($r >= $onPage) {
                fail(io.sprintf("page %d has more rows than its deleted-row marks", $page));
            }
            if (($data[$bitmap + $r // 8] & (0x80 >> ($r % 8))) != 0) {
                $deleted = $deleted + 1;
                if ($deleted > $m.deletedRows) {
                    fail(io.sprintf(
                        "more deleted rows than the %d the file declares",
                        $m.deletedRows));
                }
                continue;
            }
            if ($got == $live) {
                fail(io.sprintf("more rows than the %d the file declares", $live));
            }
            $parts[] = $data[$start + $r * $rl..$start + ($r + 1) * $rl];
            $got = $got + 1;
        }
    }
    if ($got != $live) {
        fail(io.sprintf("the file declares %d rows but holds %d", $live, $got));
    }
    return binary.join($parts);
}

/**
 * A row moved to another page, read through its reference.
 *
 * @param data {bytes} the file
 * @param head {Sas7Head} the header
 * @param pages {Sas7Pages} the pages
 * @param page {int} the page it is on, from 1 (the pointer's offset field)
 * @param index {int} its subheader pointer on that page, from 1 (the length field)
 * @param rl {int} the row length
 * @param compression {string} `rle`, `rdc` or `""`
 * @return {bytes} the row
 */
func sas7Moved(
    data as bytes,
    head as Sas7Head,
    pages as Sas7Pages,
    page as int,
    index as int,
    rl as int,
    compression as string) {
    if ($page < 1 or $page > $head.pageCount) {
        fail(io.sprintf("a moved row on page %d of %d", $page, $head.pageCount));
    }
    $page = $page - 1;
    $index = $index - 1;
    def t as int init $pages.types[$page];
    if (($t & SAS7_PAGE_MASK) == SAS7_PAGE_DATA or ($t & SAS7_PAGE_SKIP) != 0 or
        $index >= $pages.pointerCount[$page]) {
        fail(io.sprintf(
            "a moved row refers to subheader %d of page %d, which is not there",
            $index + 1,
            $page + 1));
    }
    def i as int init $pages.firstPointer[$page] + $index;
    def comp as int init $pages.ptrComps[$i];
    def size as int init $pages.ptrLengths[$i];
    if ($size <= 0) {
        fail(io.sprintf("a moved row refers to an empty subheader on page %d", $page + 1));
    }
    if ($comp == SAS7_COMP_NONE_MOVED) {
        if ($pages.ptrFlags[$i] == 0 or $pages.ptrKinds[$i] != SAS7_SH_DATA or $size != $rl) {
            fail(io.sprintf("a moved row on page %d that is not a row", $page + 1));
        }
        return $data[$pages.ptrOffsets[$i]..$pages.ptrOffsets[$i] + $size];
    }
    if ($comp == SAS7_COMP_ROW_MOVED) {
        return sas7Unpack($data, $pages.ptrOffsets[$i], $size, $rl, $compression);
    }
    fail(io.sprintf("a moved row on page %d of compression code %d", $page + 1, $comp));
    return binary.make(0);
}

/**
 * Unpack one compressed row.
 *
 * @param data {bytes} the file
 * @param at {int} the compressed row's offset
 * @param size {int} its length
 * @param rl {int} the row length it must unpack to
 * @param compression {string} `rle` or `rdc`
 * @return {bytes} the row
 */
func sas7Unpack(data as bytes, at as int, size as int, rl as int, compression as string) {
    if ($compression == "rdc") {
        return sas7Rdc($data, $at, $at + $size, $rl);
    }
    if ($compression == "rle") {
        return sas7Rle($data, $at, $at + $size, $rl);
    }
    fail("a compressed row in a file that names no compression");
    return binary.make(0);
}

/**
 * Unpack a row compressed with SAS's run-length scheme (`SASYZCRL`). Each
 * command byte holds the command in its high nibble and a length in its
 * low one: copy a run of literal bytes, or insert a run of one byte
 * (given, `@`, blank or NUL).
 *
 * @param data {bytes} the file
 * @param from {int} the first compressed byte
 * @param end {int} the byte after the last
 * @param rl {int} the row length
 * @return {bytes} the row
 */
func sas7Rle(data as bytes, from as int, end as int, rl as int) {
    def parts as list of bytes init [];
    def out as int init 0;
    def at as int init $from;
    while ($at < $end) {
        def control as int init $data[$at];
        def cmd as int init $control >> 4;
        def n as int init $control & 0x0F;
        $at = $at + 1;
        def copy as int init 0;
        def insert as int init 0;
        def fill as int init 0;
        if ($cmd <= 1 or $cmd == 4 or $cmd == 5 or $cmd == 6 or $cmd == 7 or $cmd == 12) {
            if ($at >= $end) {
                fail("a compressed row ends inside a command");
            }
        }
        if ($cmd == 0) {
            $copy = $data[$at] + 64 + $n * 256;
            $at = $at + 1;
        } elseif ($cmd == 1) {
            $copy = $data[$at] + 64 + $n * 256 + 4096;
            $at = $at + 1;
        } elseif ($cmd == 2) {
            $copy = $n + 96;
        } elseif ($cmd == 4) {
            if ($at + 1 >= $end) {
                fail("a compressed row ends inside a command");
            }
            $insert = $data[$at] + 18 + $n * 256;
            $fill = $data[$at + 1];
            $at = $at + 2;
        } elseif ($cmd == 5 or $cmd == 6 or $cmd == 7) {
            $insert = $data[$at] + 17 + $n * 256;
            $fill = [64, 32, 0][$cmd - 5];
            $at = $at + 1;
        } elseif ($cmd >= 8 and $cmd <= 11) {
            $copy = $n + 1 + 16 * ($cmd - 8);
        } elseif ($cmd == 12) {
            $insert = $n + 3;
            $fill = $data[$at];
            $at = $at + 1;
        } elseif ($cmd >= 13) {
            $insert = $n + 2;
            $fill = [64, 32, 0][$cmd - 13];
        } else {
            fail(io.sprintf(
                "an unknown command 0x%s in a compressed row",
                io.sprintf("%d|base=16", $control)));
        }
        if ($out + $copy + $insert > $rl) {
            fail(io.sprintf("a compressed row unpacks to more than %d bytes", $rl));
        }
        if ($copy > 0) {
            if ($at + $copy > $end) {
                fail("a compressed row ends inside a run of literal bytes");
            }
            $parts[] = $data[$at..$at + $copy];
            $at = $at + $copy;
            $out = $out + $copy;
        } else {
            $parts[] = binary.make($insert, $fill);
            $out = $out + $insert;
        }
    }
    if ($out != $rl) {
        fail(io.sprintf("a compressed row unpacks to %d bytes, not %d", $out, $rl));
    }
    return binary.join($parts);
}

/**
 * Unpack a row compressed with Ross Data Compression (`SASYZCR2`). A
 * 16-bit control word (big-endian) says for each of the next 16 items
 * whether it is a literal byte (bit clear) or a command: a run of one byte,
 * or a copy of earlier output of this row.
 *
 * @param data {bytes} the file
 * @param from {int} the first compressed byte
 * @param end {int} the byte after the last
 * @param rl {int} the row length
 * @return {bytes} the row
 */
func sas7Rdc(data as bytes, from as int, end as int, rl as int) {
    def older as list of bytes init [];
    def parts as list of bytes init [];
    def out as int init 0;
    def at as int init $from;
    while ($at + 2 <= $end) {
        def prefix as int init $data[$at] * 256 + $data[$at + 1];
        $at = $at + 2;
        def bit as int init 0;
        while ($bit < 16 and $at < $end) {
            def rest as int init ($prefix << $bit) & 0xFFFF;
            if (($rest & 0x8000) == 0) {
                # a run of literal bytes: the clear bits before the next set one
                def n as int init 16;
                if ($rest != 0) {
                    $n = 0;
                    while (($rest & 0xF000) == 0) {
                        $n = $n + 4;
                        $rest = $rest << 4;
                    }
                    $n = $n + SAS7_CLZ4[$rest >> 12];
                }
                $n = math.min($n, math.min(16 - $bit, $end - $at));
                if ($out + $n > $rl) {
                    fail(io.sprintf("a compressed row unpacks to more than %d bytes", $rl));
                }
                $parts[] = $data[$at..$at + $n];
                $at = $at + $n;
                $out = $out + $n;
                $bit = $bit + $n;
                continue;
            }
            $bit = $bit + 1;
            if ($at + 2 > $end) {
                fail("a compressed row ends inside a command");
            }
            def marker as int init $data[$at];
            def kind as int init $marker >> 4;
            if ($kind <= 1) {
                # a run of one byte: 3 to 18, or 19 to 4114 long
                def n as int init 3 + $marker;
                def fill as int init $data[$at + 1];
                $at = $at + 2;
                if ($kind == 1) {
                    if ($at >= $end) {
                        fail("a compressed row ends inside a command");
                    }
                    $n = 19 + ($marker & 0x0F) + $fill * 16;
                    $fill = $data[$at];
                    $at = $at + 1;
                }
                if ($out + $n > $rl) {
                    fail(io.sprintf("a compressed row unpacks to more than %d bytes", $rl));
                }
                $parts[] = binary.make($n, $fill);
                $out = $out + $n;
                continue;
            }
            # a copy of earlier output: 3 to 15, or 16 to 271 bytes
            def back as int init 3 + ($marker & 0x0F) + $data[$at + 1] * 16;
            def copy as int init $kind;
            $at = $at + 2;
            if ($kind == 2) {
                if ($at >= $end) {
                    fail("a compressed row ends inside a command");
                }
                $copy = 16 + $data[$at];
                $at = $at + 1;
            }
            if ($out + $copy > $rl) {
                fail(io.sprintf("a compressed row unpacks to more than %d bytes", $rl));
            }
            if ($back > $out) {
                fail("a compressed row copies from before its start");
            }
            # the copy reads the last `back` (at most 4098) bytes: join the
            # recent parts into a window, and move all but its last 4098
            # bytes to `older` once it grows, so a copy costs no more than
            # the window, not the row so far
            def sofar as bytes init binary.join($parts);
            def from2 as int init len($sofar) - $back;
            $parts = [$sofar];
            if (len($sofar) > 2 * SAS7_RDC_WINDOW) {
                $older[] = $sofar[..len($sofar) - SAS7_RDC_WINDOW];
                $parts = [$sofar[len($sofar) - SAS7_RDC_WINDOW..len($sofar)]];
            }
            if ($copy <= $back) {
                $parts[] = $sofar[$from2..$from2 + $copy];
            } else {
                # an overlapping copy repeats the bytes it has just written
                def done as int init 0;
                while ($done < $copy) {
                    def n as int init math.min($copy - $done, $back);
                    $parts[] = $sofar[$from2..$from2 + $n];
                    $done = $done + $n;
                }
            }
            $out = $out + $copy;
        }
    }
    if ($at != $end) {
        fail("a compressed row ends inside a control word");
    }
    if ($out != $rl) {
        fail(io.sprintf("a compressed row unpacks to %d bytes, not %d", $out, $rl));
    }
    $older[] = binary.join($parts);
    return binary.join($older);
}

/**
 * The missing code of a NaN's tag byte, the complement of its third byte
 * from the top. SAS writes either the tag's ASCII code (`.`, `A` to `Z`,
 * `_`) or its index (0 for `._`, 2 to 27 for `.A` to `.Z`); ReadStat
 * takes both, and so does this. Any other NaN is `.`.
 *
 * @param b {int} the tag byte, 0 to 255
 * @return {string} the code
 */
func sas7Tag(b as int) {
    if ($b == 0 or $b == 0x5f) {
        return "._";
    }
    if ($b >= 2 and $b <= 27) {
        return "." + convert.fromCodepoint($b - 2 + 0x61);
    }
    if ($b >= 0x41 and $b <= 0x5a) {
        return "." + convert.fromCodepoint($b + 32);
    }
    return MISSING_SYSTEM;
}

/**
 * Decode every column out of the row buffer. Numbers are read in bulk:
 * the top two bytes of every NaN (a missing value) are cleared in a copy
 * of the buffer (sas7Clean), so `readFloats` reads each 8-byte column in
 * one call and sas7ShortColumns the shorter ones; then one pass over the
 * NaNs sets their code and a 0.0.
 *
 * @param flat {bytes} the rows
 * @param head {Sas7Head} the header
 * @param m {Sas7Meta} the metadata
 * @param variables {list of Variable} the variables
 * @param rows {int} the number of rows
 * @return {Dataset} the data set
 */
func sas7Decode(
    flat as bytes,
    head as Sas7Head,
    m as Sas7Meta,
    variables as list of Variable,
    rows as int) {
    def numbers as list of list of float init [];
    def texts as list of list of string init [];
    def missing as list of list of string init [];
    def present as list of string init [];
    if ($m.columnCount > 0) {
        for (def r in 0..$rows) {
            $present[] = "";
        }
    }
    def marks as Sas7Marks init Sas7Marks{marked: binary.make(0), owner: []};
    def clean as bytes init $flat;
    if ($rows > 0 and $m.columnCount > 0) {
        $marks = sas7Marks($flat, $m, $head.order);
        $clean = sas7Clean($flat, $marks.marked, $m.rowLength);
    }
    for (def i in 0..$m.columnCount) {
        $missing[] = $present;
        if (not $m.numeric[$i]) {
            $numbers[] = [];
            $texts[] = xptTexts(
                $flat,
                $m.offsets[$i],
                $rows,
                $m.widths[$i],
                $m.rowLength,
                $head.charset);
            continue;
        }
        $texts[] = [];
        if ($rows > 0 and $m.widths[$i] == 8) {
            $numbers[] = sas7Floats(
                $clean,
                $head.order,
                $m.offsets[$i],
                $rows,
                $m.rowLength,
                $variables[$i].name);
        } else {
            $numbers[] = [];
        }
    }
    if ($rows > 0 and $m.columnCount > 0) {
        $numbers = sas7ShortColumns($numbers, $clean, $flat, $head.order, $m, $rows, $variables);
        # the NaNs: their code from the tag byte (the third from the top), and
        # 0.0 for the number read from the cleared bytes
        def codes as list of string init sas7MissingCodes();
        def tag as int init -1;
        if ($head.order == "be") {
            $tag = 2;
        }
        def rl as int init $m.rowLength;
        def needle as bytes init binary.make(2, 0xAA);
        $needle[1] = 0x55;
        def marked as bytes init $marks.marked;
        def owner as list of int init $marks.owner;
        def at as int init binary.indexOf($marked, $needle);
        while ($at >= 0) {
            $missing[$owner[$at % $rl]][$at // $rl] = $codes[$flat[$at + $tag]];
            $numbers[$owner[$at % $rl]][$at // $rl] = 0.0;
            $at = binary.indexOf($marked, $needle, $at + 2);
        }
        # a tag byte of 0 is `.`, or an infinity (an error); tell them apart
        # one cell at a time
        for (def i in 0..$m.columnCount) {
            if (not $m.numeric[$i] or not lists.contains($missing[$i], SAS7_MAYBE_INFINITE)) {
                continue;
            }
            for (def r in 0..$rows) {
                if ($missing[$i][$r] == SAS7_MAYBE_INFINITE) {
                    def col as Sas7Column init sas7Numbers(
                        sas7RawColumn(
                            $flat,
                            $r * $rl + $m.offsets[$i],
                            1,
                            $m.widths[$i],
                            $rl,
                            $head.order),
                        $variables[$i].name);
                    $missing[$i][$r] = $col.missing[0];
                }
            }
        }
    }
    return Dataset{
        format: "sas7bdat",
        version: $head.release,
        name: decodeText($head.name, $head.charset),
        label: decodeText(sas7TextBytes($m, $m.labelRef, 0), $head.charset),
        encoding: $head.charset,
        rowCount: $rows,
        variables: $variables,
        numbers: $numbers,
        texts: $texts,
        missing: $missing
    };
}

/**
 * The missing code of every tag byte as stored (the complement of the
 * tag, see sas7Tag); a stored 0 is SAS7_MAYBE_INFINITE, `.` unless the
 * value is an infinity.
 *
 * @return {list of string} 256 codes
 */
func sas7MissingCodes() {
    def out as list of string init [SAS7_MAYBE_INFINITE];
    for (def b in 1..256) {
        $out[] = sas7Tag((~ $b) & 0xFF);
    }
    return $out;
}

/**
 * Mark the NaNs and infinities (exponent bits all set) of the numeric
 * columns. Two bulk operations over the row buffer turn the top two bytes
 * of every such value into the pair 0xAA 0x55 and every other byte into
 * something else (0 outside the numeric columns' top bytes; the byte after
 * a top byte can never be 0xAA), so `binary.indexOf` and `binary.split`
 * find exactly them.
 *
 * @param flat {bytes} the rows
 * @param m {Sas7Meta} the metadata
 * @param order {string} `le` or `be`
 * @return {Sas7Marks} the marked buffer, and per byte of a row the column
 *   whose top bytes start there (-1 for none)
 */
func sas7Marks(flat as bytes, m as Sas7Meta, order as string) {
    def rl as int init $m.rowLength;
    def andKey as bytes init binary.make($rl);
    def xorKey as bytes init binary.make($rl);
    def owner as list of int init [];
    for (def k in 0..$rl) {
        $owner[] = -1;
    }
    for (def i in 0..$m.columnCount) {
        if (not $m.numeric[$i]) {
            continue;
        }
        # the top byte holds the sign and 7 exponent bits, the next one the
        # other 4 exponent bits in its high nibble
        def top as int init $m.offsets[$i];
        def masks as list of int init [0x7F, 0xF0];
        if ($order == "le") {
            $top = $m.offsets[$i] + $m.widths[$i] - 2;
            $masks = [0xF0, 0x7F];
        }
        $andKey[$top] = $masks[0];
        $andKey[$top + 1] = $masks[1];
        $xorKey[$top] = $masks[0] ^ 0xAA;
        $xorKey[$top + 1] = $masks[1] ^ 0x55;
        $owner[$top] = $i;
    }
    return Sas7Marks{marked: binary.bitXor(binary.bitAnd($flat, $andKey), $xorKey), owner: $owner};
}

/**
 * A copy of the rows with the top two bytes of every NaN and infinity
 * cleared, so that every number reads as a finite double. The marks'
 * pairs are swapped (0xAA 0x55 to 0x55 0xAA) by splitting and joining;
 * XOR with the marks then sets exactly their bytes, whose complement is
 * the mask. The rows go in chunks of at most 1 MiB, so a chunk splits into
 * fewer parts than `binary.split` allows (a pair never spans two rows).
 *
 * @param flat {bytes} the rows
 * @param marked {bytes} from sas7Marks
 * @param rl {int} the row length
 * @return {bytes} the cleared rows
 */
func sas7Clean(flat as bytes, marked as bytes, rl as int) {
    def needle as bytes init binary.make(2, 0xAA);
    $needle[1] = 0x55;
    if (not binary.contains($marked, $needle)) {
        return $flat;
    }
    def swapped as bytes init binary.make(2, 0x55);
    $swapped[1] = 0xAA;
    def step as int init math.max(1, 1048576 // $rl) * $rl;
    def parts as list of bytes init [];
    def at as int init 0;
    while ($at < len($marked)) {
        def end as int init math.min($at + $step, len($marked));
        def chunk as bytes init $marked[$at..$end];
        $parts[] = binary.join(binary.split($chunk, $needle), $swapped);
        $at = $end;
    }
    def set as bytes init binary.bitXor($marked, binary.join($parts));
    return binary.bitAnd($flat, binary.bitNot($set));
}

/**
 * Decode every numeric column of 3 to 7 bytes in bulk. Such a number is a
 * double whose low-order bytes were cut off: the stored bytes are its top
 * ones (at the field's end in a little-endian file, at its start in a
 * big-endian one). The columns go into groups whose 8-byte windows (the
 * field and the bytes that would complete it to a double) do not overlap,
 * also across the end of a row. Per group, one `bitAnd` with a row-length
 * mask keeps only the group's fields, so each window holds the field and
 * zeros; one `readFloats` per column reads the windows as doubles, the
 * same values a cell by cell conversion (sas7Numbers) gives. A window
 * that starts before the first row or ends after the last one is
 * converted on its own, as are the columns of a row shorter than 8 bytes.
 *
 * @param numbers {list of list of float} per column, its numbers so far
 * @param clean {bytes} the rows, NaNs cleared (sas7Clean)
 * @param flat {bytes} the rows as stored
 * @param order {string} `le` or `be`
 * @param m {Sas7Meta} the metadata
 * @param rows {int} the number of rows, at least 1
 * @param variables {list of Variable} the variables, for messages
 * @return {list of list of float} the numbers, those columns filled in
 *   (a NaN's number is left to the caller)
 */
func sas7ShortColumns(
    numbers as list of list of float,
    clean as bytes,
    flat as bytes,
    order as string,
    m as Sas7Meta,
    rows as int,
    variables as list of Variable) {
    def rl as int init $m.rowLength;
    def n as int init $m.columnCount;
    # each column's window start, and the short columns in window order
    def starts as list of int init [];
    def keys as list of int init [];
    for (def i in 0..$n) {
        def ws as int init $m.offsets[$i];
        if ($order == "le") {
            $ws = $m.offsets[$i] + $m.widths[$i] - 8;
        }
        $starts[] = $ws;
        if ($m.numeric[$i] and $m.widths[$i] < 8) {
            $keys[] = ($ws + 8) * $n + $i;
        }
    }
    # first fit: a group takes a column whose window starts after the
    # group's last one ends and ends before its first one starts in the
    # next row
    def firsts as list of int init [];
    def lasts as list of int init [];
    def masks as list of bytes init [];
    def members as list of list of int init [];
    for (def key in lists.sort($keys)) {
        def i as int init $key % $n;
        def ws as int init $starts[$i];
        if ($rl < 8) {
            def all as Sas7Column init sas7Numbers(
                sas7RawColumn($flat, $m.offsets[$i], $rows, $m.widths[$i], $rl, $order),
                $variables[$i].name);
            $numbers[$i] = $all.numbers;
            continue;
        }
        def g as int init 0;
        while ($g < len($firsts) and ($lasts[$g] > $ws or $ws + 8 > $firsts[$g] + $rl)) {
            $g = $g + 1;
        }
        if ($g == len($firsts)) {
            $firsts[] = $ws;
            $lasts[] = $ws;
            $masks[] = binary.make($rl);
            $members[] = [];
        }
        $lasts[$g] = $ws + 8;
        $members[$g][] = $i;
        for (def k in $m.offsets[$i]..$m.offsets[$i] + $m.widths[$i]) {
            $masks[$g][$k] = 0xFF;
        }
    }
    for (def g in 0..len($members)) {
        def masked as bytes init binary.bitAnd($clean, $masks[$g]);
        for (def i in $members[$g]) {
            def ws as int init $starts[$i];
            # the rows whose window lies inside the buffer
            def r0 as int init 0;
            def r1 as int init $rows;
            if ($ws < 0) {
                $r0 = 1;
            }
            if ($ws + 8 > $rl) {
                $r1 = $rows - 1;
            }
            $numbers[$i] = sas7Floats(
                $masked,
                $order,
                $r0 * $rl + $ws,
                $r1 - $r0,
                $rl,
                $variables[$i].name);
            if ($r0 == 1) {
                def first as Sas7Column init sas7Numbers(
                    sas7RawColumn($flat, $m.offsets[$i], 1, $m.widths[$i], $rl, $order),
                    $variables[$i].name);
                $numbers[$i] = lists.concat($first.numbers, $numbers[$i]);
            }
            if ($r1 == $rows - 1) {
                def last as Sas7Column init sas7Numbers(
                    sas7RawColumn($flat, $r1 * $rl + $m.offsets[$i], 1, $m.widths[$i], $rl, $order),
                    $variables[$i].name);
                $numbers[$i] = lists.concat($numbers[$i], $last.numbers);
            }
        }
    }
    return $numbers;
}

/**
 * Read a column of doubles whose NaNs have been made finite.
 *
 * @param b {bytes} the buffer
 * @param order {string} `le` or `be`
 * @param at {int} the first value's offset
 * @param count {int} the number of values
 * @param stride {int} the row length
 * @param name {string} the variable, for the message
 * @return {list of float} the values
 */
func sas7Floats(
    b as bytes,
    order as string,
    at as int,
    count as int,
    stride as int,
    name as string) {
    try {
        return binary.readFloats($order, $b, $at, $count, 8, $stride);
    } catch (e) {
        # only when columns overlap, which no writer does
        fail("numeric column " + $name + " overlaps another one");
    }
    return [];
}

/**
 * The 64-bit patterns of one numeric column. A number stored in fewer than
 * 8 bytes keeps its most significant bytes; the rest are zero. The bytes
 * are read in at most three bulk reads of 4, 2 and 1 bytes per value.
 *
 * @param flat {bytes} the rows
 * @param start {int} the offset of the first row's value
 * @param rows {int} the number of rows
 * @param width {int} the stored length, 3 to 8
 * @param stride {int} the row length
 * @param order {string} `le` or `be`
 * @return {list of int} one pattern per row
 */
func sas7RawColumn(
    flat as bytes,
    start as int,
    rows as int,
    width as int,
    stride as int,
    order as string) {
    if ($rows == 0) {
        return [];
    }
    if ($width == 8) {
        return binary.readInts($order, $flat, $start, $rows, 8, $stride);
    }
    def out as list of int init [];
    def offset as int init 0;
    for (def size in [4, 2, 1]) {
        if ($width - $offset < $size) {
            continue;
        }
        def part as list of int init binary.readInts(
            $order,
            $flat,
            $start + $offset,
            $rows,
            $size,
            $stride);
        def mask as int init (1 << (8 * $size)) - 1;
        def shift as int init 8 * (8 - $width + $offset);
        if ($order == "be") {
            $shift = 8 * (8 - $offset - $size);
        }
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

/**
 * Convert one column of IEEE double bit patterns: the 53-bit significand
 * times a power of two, both exact. A NaN is a missing value; an infinity
 * is an error (SAS cannot store one).
 *
 * @param raws {list of int} the patterns
 * @param name {string} the variable, for the message
 * @return {Sas7Column} the numbers (0.0 where missing) and missing codes
 */
func sas7Numbers(raws as list of int, name as string) {
    def nums as list of float init [];
    def miss as list of string init [];
    for (def raw in $raws) {
        def e as int init ($raw >> 52) & 0x7FF;
        def frac as int init $raw & 0xFFFFFFFFFFFFF;
        if ($e == 0x7FF) {
            if ($frac == 0) {
                fail("an infinite value of " + $name);
            }
            $nums[] = 0.0;
            $miss[] = sas7Tag((~ ($raw >> 40)) & 0xFF);
            continue;
        }
        def x as float;
        if ($e == 0) {
            $x = convert.toFloat($frac) * math.pow(2.0, -1074);
        } else {
            $x = convert.toFloat($frac | 0x10000000000000) * math.pow(2.0, $e - 1075);
        }
        if ($raw < 0) {
            $x = -$x;
        }
        $nums[] = $x;
        $miss[] = "";
    }
    return Sas7Column{numbers: $nums, missing: $miss};
}
