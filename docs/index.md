<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/statfiles

Readers for the data files of the big statistics packages, so a Jennifer
program can take study and survey data as it arrives: Stata `.dta`
(formats 104 to 119), SPSS `.sav`, `.zsav` and portable `.por`, SAS
XPORT `.xpt` (versions 5 and 8, the FDA submission format), and SAS data
sets `.sas7bdat` with the value labels of `.sas7bcat` catalogs. Read-only:
nothing is written. Pure Jennifer, no capability needed.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/statfiles/" as statfiles;
```

## Reading a file

A reader takes the file's bytes; `read` recognises the format from its
first bytes.

```jennifer
def ds as statfiles.Dataset init statfiles.read(fs.readBytes("survey.sav"));
io.printf("%s, %d rows\n", $ds.format, $ds.rowCount);
for (def v in $ds.variables) {
    io.printf("%s|pad=10 %s|pad=8 %s\n", $v.name, $v.type, $v.label);
}
```

`detect` names the format without reading it. `readDta`, `readSav`,
`readPor`, `readXpt` and `readSas7bdat` read one format and refuse the
others; an XPORT file with several datasets is read with
`readXptMembers`, a SAS format catalog with `readSas7bcat`.

## The dataset

A `Dataset` holds its cells by column: entry `i` of `numbers`, `texts` and
`missing` belongs to `variables[i]`. A numeric variable's values are
`float`, whatever the file stored (Stata's `byte` to `double`, SAS's
shortened numbers). A string variable's values keep their trailing blanks
in Stata, where blanks are data, and lose them in SPSS and SAS, whose
fixed-width fields are padded with blanks. Variables keep their label,
display format, value labels and, in SPSS, the declared missing values;
`width` is the bytes a value takes in the file (a number's stored size,
0 in a `.por`).

```jennifer
def ages as list of float init statfiles.present($ds, "age");
io.printf("mean age %.1f of %d\n", stats.mean($ages), len($ages));
io.printf("%s\n", statfiles.labelOf($ds, "sex", 0));   # "female"
fs.writeString("survey.csv", statfiles.toCsv($ds, true));
```

`column` gives every value of a variable, one per row, for `stats` and
`linalg`; it refuses a variable with a missing cell, so the values never
shift against the rows. `present` leaves the missing cells out.

## Missing values

Jennifer has no NaN, so a missing cell has a missing code instead:

| Code | Meaning |
|---|---|
| `""` | present |
| `.` | system missing: Stata's and SAS's `.`, SPSS's SYSMIS |
| `.a` to `.z` | Stata's extended codes, SAS's `.A` to `.Z` |
| `._` | SAS's `._` |
| `user` | a value SPSS declares missing; the value is kept |

`missingCode` and `isMissing` read it per cell. `number` returns a `user`
value and refuses the others; `toCsv` writes a missing number as an empty
field.

## Encodings

Text is decoded with the character set the file declares, else the
format's default (Windows-1252 for Stata before 118, for SAS XPORT and
for a `.sas7bdat` that declares none).
`Options.encoding` overrides both:

```jennifer
def opts as statfiles.Options init statfiles.options();
$opts.encoding = "iso-8859-2";
def ds as statfiles.Dataset init statfiles.readWith(fs.readBytes("old.dta"), $opts);
```

## Errors and limits

A malformed or truncated file, an unknown format or a bad argument throws
`Error{kind: "statfiles"}`; nothing is patched up silently. A file over a
cap is kind `"limit"`: `Options.maxCells` (20 million cells by default)
bounds every reader before it allocates, and `Options.maxBytes` (256 MiB)
the size compressed SPSS cases unpack to (a few bytes of bytecode can
stand for kilobytes of blank long strings).

A read dataset takes about 1.2 KB of memory per cell (the interpreter's
values, whatever the format), so a file of 20 million cells, the
`maxCells` default, needs about 23 GB. Lower `maxCells` to what the
machine can hold.

```jennifer
try {
    def ds as statfiles.Dataset init statfiles.read($data);
} catch (e) {
    io.printf("%s: %s\n", $e.kind, $e.message);
}
```

## Speed

The readers are pure Jennifer, so a large file takes a while: 10,000 rows
of 20 variables (16 numeric, 4 string) read in about 0.5 s from a Stata
file, 0.6 s from an uncompressed `.sav`, 0.7 s from an uncompressed
`.sas7bdat` (numbers of 3 to 8 bytes alike), 1.2 s from a compressed
`.sav`, a `.zsav` or an XPORT file,
2 to 3.5 s from a compressed `.sas7bdat`, and 8 s from a `.por`, whose
base-30 numbers are decoded one digit at a time.

## Not covered

Writing any format; SPSS multiple-response sets, attributes and
documents; Stata notes and characteristics; SAS views, indexes and
encrypted data sets, and catalog labels of ranges (see
[SAS data sets and format catalogs](sas7bdat.md)).
