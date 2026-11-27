<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# SAS data sets and format catalogs

The deck reads SAS™'s own data sets (`.sas7bdat`) and the value labels of
SAS format catalogs (`.sas7bcat`). SAS does not document either format;
the readers follow the reverse engineering of ReadStat™, parso, pandas and
Matthew Shotwell's notes for the sas7bdat R package, and were checked
cell by cell against pyreadstat (ReadStat) and pandas on about 350
sample files and 590 generated ones.

Covered: 32- and 64-bit files, either byte order, uncompressed files and
files whose rows SAS compressed with `COMPRESS=CHAR` (RLE, `SASYZCRL`) or
`COMPRESS=BINARY` (RDC, `SASYZCR2`), rows moved to another page of a
compressed file, deleted rows, metadata amended on AMD pages, and files from
Stat/Transfer.

## Reading a data set

```jennifer
import "@deckyard/statfiles/" as statfiles;

def ds as statfiles.Dataset init statfiles.readSas7bdat(fs.readBytes("cars.sas7bdat"), statfiles.options());
io.printf("%s: %d rows, written by SAS %s\n", $ds.name, $ds.rowCount, $ds.version);
```

`statfiles.read(data)` detects the format and calls `readSas7bdat`;
`statfiles.detect(data)` names a data set `sas7bdat` and a catalog
`sas7bcat`. `Dataset.format` is `sas7bdat`, `Dataset.version` the SAS
release in the header (`9.0401M5` is SAS 9.4 M5) and `Dataset.name` the
data set's name.

## What maps to what

| sas7bdat | Dataset |
|---|---|
| the data set name in the header | `Dataset.name` |
| the data set label (row size subheader) | `Dataset.label` |
| the SAS release in the header | `Dataset.version` |
| column type 1, stored in 3 to 8 bytes | `type` and `storage` `numeric`, `width` the stored length (3 to 8) |
| column type 2 | `type` and `storage` `string`, `width` the stored length |
| column name and label | `Variable.name`, `Variable.label` |
| format name, width and decimals | `Variable.format`, written as SAS does: `DATE9.`, `BEST12.`, `$CHAR20.`, `8.2`, `""` when none |

The informat is not kept. `missingValues` and `missingRange` stay empty
(SAS has no declared missing values); `valueLabels` is filled from a
catalog by `withSasLabels`.

## Numbers, dates and missing values

A number is an IEEE double. SAS may store it in fewer than 8 bytes
(`LENGTH x 4;`), dropping the low-order bytes; the reader pads them with
zeros, as SAS does, so a value stored in 4 bytes reads back with the
precision it was stored with.

Dates, times and datetimes stay numbers with their format: a `DATE9.` or
`YYMMDD10.` value counts days since 1960-01-01, a `DATETIME20.` value
seconds since 1960-01-01 00:00, a `TIME8.` value seconds since midnight.

A missing number is a NaN whose third byte from the top carries the
code. Its code in `Dataset.missing`, with the number itself 0.0:

| SAS | code |
|---|---|
| `.` (and any other NaN) | `.` |
| `.A` to `.Z` | `.a` to `.z` |
| `._` | `._` |

`statfiles.column(ds, name)` throws on any missing cell;
`statfiles.present(ds, name)` leaves them out. An infinity, which SAS
cannot store, is an error.

A string is decoded and its trailing blanks are dropped. SAS has no
missing string: an empty one is `""` with the code `""`.

## Deleted rows

A row that SAS marks deleted is left out: in an uncompressed file a bitmap
after a page's rows marks them, in a compressed one the row's subheader
pointer. `rowCount` counts the rows that are left, as SAS, ReadStat and
parso do (pandas 3.1 keeps them).

## Encoding

The header names the character set (byte 70). Text is decoded from it
unless `Options.encoding` names another; a file that names none (code 0,
or SAS's `any`) is read as windows-1252. UTF-8, US-ASCII, the ISO-8859
sets and the Windows code pages 1250 to 1258 are supported. A file in
another character set (DOS code pages, Mac encodings, Shift-JIS, EUC,
Big5, GB18030, ...) throws kind `"statfiles"` naming it; set
`Options.encoding` to read it anyway, for example `iso-8859-1` when its
text is plain ASCII:

```jennifer
def opts as statfiles.Options init statfiles.options();
$opts.encoding = "iso-8859-1";
def ds as statfiles.Dataset init statfiles.readSas7bdat(fs.readBytes("cjk.sas7bdat"), $opts);
```

Names, labels and formats are decoded the same way.

## Value labels from a format catalog

SAS keeps value labels apart from the data, in a format catalog written
by `PROC FORMAT` (`formats.sas7bcat`). A variable names its format in
`Variable.format`. `statfiles.readSas7bcat(data, opts)` reads every value
format of a catalog; `statfiles.withSasLabels(ds, catalog)` gives each
variable the labels of its format:

```jennifer
def ds as statfiles.Dataset init statfiles.readSas7bdat(fs.readBytes("survey.sas7bdat"), statfiles.options());
def formats as map of string to map of string to string init statfiles.readSas7bcat(
    fs.readBytes("formats.sas7bcat"),
    statfiles.options());
$ds = statfiles.withSasLabels($ds, $formats);
io.printf("%s\n", statfiles.labelOf($ds, "sex", 0));   # "Female"
```

The catalog is a map from the format's name to a map from value to label.
A format is named as `PROC FORMAT` names it, in upper case and without
the period: `GENDER` for a numeric format, `$GENDER` for a character
one. `statfiles.sasFormatName(format)` turns a variable's format into that
name (`$GENDER6.` is `$GENDER`, `DATE9.` is `DATE`, `8.2` has none).
`withSasLabels` gives character formats to string variables only and the
others to numeric variables only; variables whose format the catalog
lacks keep their labels.

Values are keyed as `labelOf` looks them up: a number as `valueKey` writes
it (`1`, `2.5`), a special missing value as its code (`.a`), a string
without trailing blanks.

Catalogs written by SAS in a UTF-8 session often name no character set,
so their text reads as windows-1252 and non-ASCII labels fail; set
`Options.encoding` to `utf-8` for them.

Not covered, and left out of the map:

- a label for a range of values, numeric or character (`1-5 = 'low'`,
  `low-<0`, `'A'-'F'`): it has no single key (ReadStat keys a range by its
  start, or by its two ends run together for a character range, which
  matches no value);
- the `OTHER` label;
- informats (`INVALUE`), and picture formats' pictures.

A format left with no label once ranges and `OTHER` are left out is not
in the map at all, as in ReadStat (not an empty map).

A label longer than its block is an error. The 32-byte label records SAS
9.4 writes for some ranges (the GSS catalogs have 2,527 of them, which
ReadStat refuses) are read and stepped over.

## Errors and limits

- A file that is not a sas7bdat file, whose size is not the header's
  page count times its page size plus the header, whose header has an
  unknown byte order or release, or whose subheaders, pointers, text
  references, columns or compressed rows contradict each other or lie
  outside their page throws kind `"statfiles"`. So does a file that holds
  more or fewer rows than it declares, or more deleted rows.
- `Options.maxCells` caps rows times variables, checked against the
  declared row count before anything is allocated; over it, kind
  `"limit"`. A file that declares more rows than it holds is an error
  once the reader has seen them all: memory grows with the rows found,
  not with the rows declared.
- `Options.maxBytes` caps the size of the unpacked rows of a compressed
  file, also checked before unpacking.
- A catalog that is not one, or whose blocks or entries contradict each
  other, throws kind `"statfiles"`. So does a block whose chain of links
  runs past a page or loops: the blocks together may not be longer than
  the file.
- A catalog longer than `Options.maxBytes` is kind `"limit"`, checked
  before it is parsed; so is one of more than `Options.maxCells` value
  labels, counted from each format's header before its labels are read
  (`OTHER` and range labels count, though they are left out of the map).

```jennifer
try {
    def ds as statfiles.Dataset init statfiles.readSas7bdat($data, statfiles.options());
} catch (e) {
    io.printf("%s: %s\n", $e.kind, $e.message);
}
```

Measured on Jennifer 0.27.0, reading 10,000 rows of 20 variables (16
numbers, 4 strings) takes about 0.7 to 1 second from an uncompressed file,
2.1 seconds from an RLE-compressed one and 3.3 seconds from an
RDC-compressed one: the compressed rows are unpacked one command at a time. Numbers are converted
in bulk, those stored in 3 to 7 bytes too; a missing value costs a few
microseconds of its own. The GSS 2021 file (4,032 rows of 943 variables,
most of them 3 to 6 bytes, 46% missing, RLE) takes about 35 seconds,
most of it unpacking rows, and 4.9 GB of memory.

Memory is about 0.2 KB per cell on Jennifer 0.28.0 (the interpreter's
values), so a file of 2 million cells, the `maxCells` default, needs about
0.5 GB; set `maxCells` to what the machine can hold. A large catalog is slow
too: the GSS 2021 `formats.sas7bcat` (146 MB, 1,638 formats, about a million
labels) took about 50 seconds and 4 GB on Jennifer 0.27.0.

## Not covered

Writing; SAS views (`.sas7bvew`), indexes (`.sas7bndx`) and other
library members; encrypted data sets (`ENCRYPT=YES` or `AES`); audit
trails and generation data sets beyond the data set itself.
