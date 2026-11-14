<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# SAS data sets and format catalogs

The deck reads SAS's own data sets (`.sas7bdat`) and the value labels of
SAS format catalogs (`.sas7bcat`). SAS does not document either format;
the readers follow the reverse engineering of ReadStat, parso, pandas and
Matthew Shotwell's notes for the sas7bdat R package, and were checked
cell by cell against pyreadstat (ReadStat) and pandas on about 190 sample
files.

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
| column type 1, stored in 3 to 8 bytes | `type` and `storage` `numeric`, `width` 0 |
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

- a label for a range of numbers (`1-5 = 'low'`): it has no single key;
- the `OTHER` label;
- informats (`INVALUE`), and picture formats' pictures;
- a character range (`'a'-'m'`): its layout is not known, and only its
  first value is read, as ReadStat does;
- a label longer than its block: ReadStat cuts it off; here it is an
  error.

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
  other, throws kind `"statfiles"`.

```jennifer
try {
    def ds as statfiles.Dataset init statfiles.readSas7bdat($data, statfiles.options());
} catch (e) {
    io.printf("%s: %s\n", $e.kind, $e.message);
}
```

Reading 10,000 rows of 20 variables takes about 0.7 seconds from an
uncompressed file, 2.2 seconds from an RLE-compressed one and 3 seconds
from an RDC-compressed one: the compressed rows are unpacked one command
at a time.

## Not covered

Writing; SAS views (`.sas7bvew`), indexes (`.sas7bndx`) and other
library members; encrypted data sets (`ENCRYPT=YES` or `AES`); audit
trails and generation data sets beyond the data set itself.
