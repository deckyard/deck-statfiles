<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# SAS XPORT files

The deck reads SAS transport files (`.xpt`) of versions 5 and 8: the
format of SAS's XPORT engine and of the `%loc2xpt` macro, which the FDA
requires for submissions. Version 5 limits names to 8 characters, labels to
40 and strings to 200 bytes; version 8 allows 32-character names, longer
labels and format names, and longer strings.

SAS's own data sets (`.sas7bdat`) and format catalogs (`.sas7bcat`) have
their own page, [SAS data sets and format catalogs](sas7bdat.md).

## Reading a file

```jennifer
import "@deckyard/statfiles/" as statfiles;

def ds as statfiles.Dataset init statfiles.readXpt(fs.readBytes("dm.xpt"), statfiles.options());
io.printf("%s: %d rows\n", $ds.name, $ds.rowCount);
```

`statfiles.read(data)` detects the format and calls `readXpt` for an XPORT
file. `Dataset.format` is `xpt` and `Dataset.version` is `5` or `8`.

## Members

A transport file is a library that can hold several data sets, its
members. `readXpt` returns the only member and throws kind `"statfiles"`
for a file of several (the message names them) or of none.
`statfiles.readXptMembers(data, opts)` returns every member in file order:

```jennifer
for (def ds in statfiles.readXptMembers(fs.readBytes("lib.xpt"), statfiles.options())) {
    io.printf("%s (%s): %d rows\n", $ds.name, $ds.label, $ds.rowCount);
}
```

The data of one member runs up to the next member header record. A string
value that holds that exact 48-byte header text at a record boundary would
end the member early; no writer is known to produce one.

## What maps to what

| XPORT | Dataset |
|---|---|
| member name (8 characters, 32 in version 8) | `Dataset.name` |
| member label (the first 40 characters) | `Dataset.label` |
| NAMESTR type 1, any length from 2 to 8 bytes | `type` and `storage` `numeric`, `width` 0 |
| NAMESTR type 2 | `type` and `storage` `string`, `width` the stored length |
| `nname`, or the version 8 long name | `Variable.name` |
| `nlabel` | `Variable.label` |
| `nform`, `nfl`, `nfd` | `Variable.format`, written as SAS does: `DATE9.`, `8.2`, `$CHAR20.`, `""` when none |
| LABELV8 / LABELV9 section (version 8) | the full name and label, and in LABELV9 the full format name |

Value labels live in a separate formats catalog, which a transport file
does not carry: `valueLabels` stays empty, as do `missingValues` and
`missingRange`. The informat is not kept.

Numbers are IBM System/360 hex floats. A value stored in fewer than 8
bytes is padded with zero bytes. Every value written from an IEEE double
reads back exactly. A fraction of more than 53 significant bits (possible
only in files from a mainframe) loses its lowest bits, truncated as SAS's
own converter does. A writer stores a value beyond the IBM range
(about 7.2e75) as the largest IBM value, which reads as
7.2370055773322614e75: Jennifer has no infinity.

A string is decoded and its trailing blanks are dropped; leading blanks
stay. An empty string is `""` and is not missing.

## Missing values

A missing number is stored as one byte followed by zero bytes. Its code in
`Dataset.missing`, with the number itself 0.0:

| stored | SAS | code |
|---|---|---|
| `.` (0x2e) | `.` | `.` |
| `A` to `Z` | `.A` to `.Z` | `.a` to `.z` |
| `_` (0x5f) | `._` | `._` |

`statfiles.column(ds, name)` throws on any missing cell;
`statfiles.present(ds, name)` leaves them out; `statfiles.missingCode(ds, name, row)`
returns the code.

## Encoding

The format records no character set. Text is decoded from windows-1252
unless `Options.encoding` names another; SAS writes the session encoding's
Windows equivalent. Files written by pyreadstat or ReadStat from Python
strings are UTF-8:

```jennifer
def opts as statfiles.Options init statfiles.options();
$opts.encoding = "utf-8";
def ds as statfiles.Dataset init statfiles.readXpt(fs.readBytes("from-python.xpt"), $opts);
```

Names and labels are decoded the same way.

## Row counts and trailing blank rows

The observations are streamed in 80-byte records and the last record is
padded with blanks, so fewer than 80 bytes of padding follow the last row.
Version 5 does not record the number of rows; the reader takes as many rows
as fit and drops the rows at the end that are all blanks and lie within the
padding. ReadStat drops such rows too (and also drops a blank row that the
last record must hold, so it reads a file of one blank row as empty).

That is ambiguous: a real last row that is all blanks (only string
variables, all empty) and fits in the padding is dropped too. A data set of
rows `a`, `b`, `""`, `""` in one 1-byte string variable reads as two rows.

A version 8 file may state its row count in the OBSV8 header record (SAS 9
and ReadStat write it); the reader then uses it, and the example above
reads as four rows. A count that the data area does not match exactly is an
error.

## Errors and limits

- A file that is not XPORT, is not a whole number of 80-byte records, ends
  inside a header or a row, has a header record out of place, a NAMESTR
  length other than 140 or 136, a variable type other than 1 or 2, a number
  stored in fewer than 2 or more than 8 bytes, a variable outside the row,
  or padding after the data that is not blank throws kind `"statfiles"`.
  A version 5 file cut at a record boundary inside its data cannot be told
  from a shorter file; a cut that leaves part of a row is an error.
- `Options.maxCells` caps rows times variables, summed over all members
  for `readXptMembers`; over it, kind `"limit"`. The cap is checked from
  the headers and the file's length before any cell is decoded.
- An `Options.encoding` the `encoding` library lacks throws kind
  `"statfiles"`.

```jennifer
try {
    def all as list of statfiles.Dataset init statfiles.readXptMembers(fs.readBytes("lib.xpt"), statfiles.options());
} catch (e) {
    io.printf("%s: %s\n", $e.kind, $e.message);
}
```

Reading takes about 1.2 seconds for 10,000 rows of 20 variables.
