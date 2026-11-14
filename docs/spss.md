<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# SPSS: .sav, .zsav and .por

`statfiles` reads the three SPSS data formats: the system file `.sav`
(uncompressed or bytecode compressed), its zlib form `.zsav`, and the
portable file `.por`. Each becomes one `Dataset`; nothing is written.

```jennifer
import "@deckyard/statfiles/" as statfiles;

def ds as statfiles.Dataset init statfiles.read(fs.readBytes("survey.sav"));
io.printf("%s: %d rows\n", $ds.label, $ds.rowCount);
io.printf("mean income %f\n", stats.mean(statfiles.present($ds, "income")));
```

`read` tells the formats apart by their first bytes (`$FL2`, `$FL3`, or
`SPSSPORT` after the portable header). `statfiles.readSav(data, opts)` and
`statfiles.readPor(data, opts)` read one format directly; `readSav` takes
both `.sav` and `.zsav`.

## What maps to what

| SPSS | `Dataset` / `Variable` |
|---|---|
| file label | `label` (`.por` has none, except ReadStat's, which it writes after the splash) |
| character set | `encoding` |
| variable name | `name`: the long name (record 7.13) in a `.sav`, the 8-character name in a `.por` |
| variable label | `label` |
| numeric / string | `type` and `storage`: `numeric` or `string` |
| string width | `width` in bytes; a very long string (over 255 bytes, stored as segments) is one variable of its full width |
| print format | `format` as SPSS writes it: `F8.2`, `A20`, `DATE11`, `COMMA9` |
| value labels | `valueLabels`, keyed by `valueKey` (`"1"`, `"2.5"`) or by the string without trailing blanks |
| missing values | `missingValues`, as `valueKey` texts or trimmed strings |
| missing range | `missingRange` `[low, high]`; `LO` is `LOWEST`, `HI` is `HIGHEST` |
| `.sav` version | `version` is always `""`; `format` is `sav`, `zsav` or `por` |

Dates stay numbers: SPSS stores them as seconds since 14 October 1582,
and `format` (`DATE11`, `DATETIME20`, `ADATE10`, ...) says how SPSS shows
them. Documents (record 6, `.por` tag `E`), display widths, measurement
levels, attributes and multiple-response sets are read past and dropped.

## System-missing and user-missing

SPSS has two kinds of missing value, and the dataset keeps them apart in
`missing`:

- **System-missing** (`SYSMIS`, an empty cell): code `.` (`MISSING_SYSTEM`),
  and `0.0` in `numbers`. Only numbers can be system-missing.
- **User-missing**: a value that matches one of the variable's declared
  missing values or falls in its range. Code `user` (`MISSING_USER`); the
  value itself stays in `numbers` or `texts`, so `number` and `text` return
  it and `labelOf` finds its label (`99` labelled `refused`).

`column` refuses both kinds; `present` drops both. To keep user-missing
values in a computation, read `numbers` and test `missing` for `.` only.

A string matches a missing value when it is equal after trailing blanks are
cut from both. A long string's missing values (record 7.22) hold its first 8
bytes, as SPSS defines them.

## Encodings

The text of a `.sav` (names, labels, value labels, string cells) is decoded
from, in this order:

1. `Options.encoding`, when set;
2. the encoding record (7.20), such as `UTF-8` or `windows-1252`;
3. the code page of the machine integer record (7.3): 65001 is UTF-8, 1250
   to 1258 the Windows code pages, 28591 to 28605 ISO 8859, 20127 ASCII;
4. `windows-1252`.

A `.por` stores text in the portable character set and maps it through the
file's 256-byte translation table. Bytes the table does not name (PSPP
writes non-ASCII text as raw UTF-8) are kept and decoded from
`Options.encoding`, else from UTF-8 when the whole file is valid UTF-8, else
from `windows-1252`.

A character set the `encoding` library lacks, or a byte it cannot decode, is
an error; set `Options.encoding` to read such a file anyway.

## Formats and their quirks

- Both byte orders of `.sav` are read; the header's layout code tells them
  apart.
- Bytecode compression uses the bias from the header. A case count of -1
  (unknown) is read until the data ends, the cell cap applying as it goes;
  the extended case count (record 7.16) is used when the header has none.
- A `.zsav` is checked block by block against its trailer before anything
  is unpacked.
- A `.por` keeps strings to 255 bytes; PSPP truncates longer ones when it
  exports. PSPP also writes a `x THRU HI` range with `HI` where `x` belongs,
  so such a range reads back as `[HIGHEST, HIGHEST]`.
- Lines of a `.por` may end in CR LF or LF; a line shorter than 80 columns
  counts as padded with blanks.

## Limits and errors

| Error kind | When |
|---|---|
| `statfiles` | not an SPSS file; a truncated or malformed header, record, case or zlib block; data after the last case; an unknown record type, format code or compression code; text that does not decode |
| `limit` | more than `Options.maxCells` cells (rows times variables); compressed cases that unpack to more than `Options.maxBytes` bytes, counting both the zlib blocks of a `.zsav` and the bytecode in the uncompressed layout (one code byte stands for 8 bytes) |

The checks are strict: a file that does not follow the format throws rather
than being patched, so a truncated download fails instead of losing rows.

```jennifer
def opts as statfiles.Options init statfiles.options();
$opts.maxCells = 1000000;
$opts.encoding = "windows-1252";
try {
    def ds as statfiles.Dataset init statfiles.readWith($data, $opts);
} catch (e) {
    io.printf("%s: %s\n", $e.kind, $e.message);
}
```

## Performance

Uncompressed numeric columns are read with one `binary.readFloats` call
each. Compressed cases are first rebuilt in the uncompressed layout. On a
10000 by 20 file (16 numeric, 4 string variables) an uncompressed `.sav`
reads in about 0.6 s, a bytecode or zlib compressed one in about 1.2 s.
A `.por` of the same table takes about 8 s, most of it in base-30 numbers,
each read to the nearest float (in `decimal` when it has more digits than
a float holds exactly).
