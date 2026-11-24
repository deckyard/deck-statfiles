<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck reads the data files of the major statistics packages, the
formats study and clinical data arrives in:

- **Stata™ `.dta`**, versions 104 to 119 (tagged sections from 117, `strL`
  in both layouts, value labels, both byte orders, `.a`-`.z`);
- **SPSS™ `.sav` and `.zsav`** (the record types PSPP™ documents, very long
  strings, bytecode compression, zlib blocks, system-missing, declared
  missing values and ranges) and the portable **`.por`** format;
- **SAS™ XPORT `.xpt`**, versions 5 and 8, several members through
  `readXptMembers`;
- **SAS `.sas7bdat`** and value labels from a **`.sas7bcat`** catalog.

It is pure Jennifer over `bytes`, with the `binary` number readers,
`compress` (zlib) and `encoding` (Windows and ISO-8859 code pages). It needs
no capability; the readers take bytes, and the caller reads the file.

Out of scope:

- **Writing** any of these formats.
- SPSS multiple-response sets, attributes and documents; Stata notes and
  characteristics.
- `.sas7bcat` ranges, OTHER labels and informats (only single-value labels
  are read).

## Decisions

- **One result type, stored by column.** `read` and `readWith` return a
  `Dataset`: per variable its name, label, type, storage, `width`, display
  format, value labels and declared missing values, and its cells in
  `numbers`, `texts` and `missing`, one list per variable. Rows of structs
  would be slow, because a deck's own structs are rebuilt on every call
  into the deck. `detect` names the format from the bytes.
- **Missing cells carry a code.** Jennifer has no NaN, so a missing cell is
  `0.0` in `numbers` with a code in `missing`: `.` (`MISSING_SYSTEM`),
  `.a`-`.z`, `._`, or `user` (`MISSING_USER`) for a value SPSS declares
  missing, whose value is kept. `column` hands a variable to `stats` or
  `linalg` and refuses one with any missing cell; `present` drops them.
- **Strict reading.** Malformed or truncated input is an error, never
  patched. A byte the file's character set lacks is an error too, rather
  than a replacement character.
- **Encodings.** `Options.encoding` wins; otherwise the file's own
  declaration; otherwise windows-1252 for Stata before 118, SAS and SPSS
  without a code page, and UTF-8 for the rest. A SAS character set the
  `encoding` library lacks (Mac, DOS, CJK) is an error that asks for
  `Options.encoding`.
- **`width` is the bytes a value takes.** A string's width (0 for a
  `strL`), a number's stored size (Stata 1 to 8, SPSS 8, `.sas7bdat` 3 to
  8, XPORT 2 to 8); `.por` numbers are text and have width 0.
- **Text as the reference readers give it.** Stata values keep trailing
  blanks and are cut only at the first NUL, as pandas and pyreadstat do;
  Stata labels and every SPSS and SAS text are trimmed.
- **Undocumented `.sas7bdat` from three readers.** The layout comes from
  ReadStat™, parso and pandas: 32- and 64-bit files, both byte orders, meta,
  data, mix and AMD pages, RLE and RDC compression, moved and deleted rows,
  numbers in 3 to 8 bytes, missing values from NaN tags. Every 64-bit field
  is range-checked before arithmetic. Numbers are decoded in bulk: the NaN
  tags are marked and cleared with byte-wise operations over whole row
  chunks, then whole columns are read as floats at once, which made
  3- to 7-byte numbers about three times faster than decoding per cell.
- **`.sas7bcat` labels.** `readSas7bcat` maps a format name (upper case, no
  period) and a value key to a label; `withSasLabels` attaches them, `$`
  formats to string variables, the others to numeric ones. A format with
  only OTHER or ranges is left out, as ReadStat does.
- **Exact `.por` numbers.** Base-30 numbers are rounded once to the
  nearest float: one float operation when that is exact, `decimal` or an
  exact digit path otherwise. Accumulating in floats was 1 to 2 ulp off on
  about half of ReadStat's values.
- **Reference-reader quirks.** XPORT version 5 drops trailing all-blank
  rows inside the last 80-byte record (ReadStat's rule), so a genuine
  all-blank last row is lost; version 8 uses the stated row count. Values
  past the IBM™ float range read as the IBM maximum. A `.por` written by
  PSPP's `x THRU HI` bug is read as written.
- **Values, labels and CSV.** `labelOf` gives a cell's value label;
  `toCsv` writes the dataset with values or labels through the bundled
  `csv` module.

## Errors

Every failure is `Error{kind: "statfiles"}` (`ERROR_KIND`), except a
reached cap, which is kind `"limit"`. Messages carry no `statfiles: `
prefix; the kind says where they come from. The readers raise nothing else on
any input: truncation and corruption sweeps give only those two kinds. The
deck reads no server and has no error struct.

## Security and limits

- `Options.maxCells` (`DEFAULT_MAX_CELLS`, 2 million) bounds the cells of
  a data set and the labels of a catalog, checked before they are read.
- `Options.maxBytes` (`DEFAULT_MAX_BYTES`, 256 MiB) bounds the `.zsav`
  zlib blocks, the expansion of SPSS bytecode (one code byte can stand for
  8 bytes) and the size of a catalog.
- Every offset, length and count read from a file is checked against what
  is left before use; `.sas7bcat` block chains must stay within their page
  and the file, since a looping chain was unbounded work.
- Memory is about 1.2 KB per cell whatever the format, so the default cell
  cap still allows a large footprint; lower it for untrusted files.

## Testing and validation

- About 107 tests over base64 fixtures in `src/topics/fixtures/`, so the
  overlays run from a bare copy of `src/`. Fixtures were written by
  pyreadstat 1.3.8, pandas, PSPP 2.0.1 and hand-made writers, plus
  third-party samples from pandas, parso, ReadStat, pyreadstat and haven
  (each with source, commit and licence) and one SAS 9.3 file from
  phuse-scripts (CDISC™ pilot data). Every fixture was checked value for
  value against pyreadstat or pandas.
- Validation on 2026-11-14, with scripts kept outside the deck: about
  3,500 random files (Stata 104 to 119 in both byte orders, `.sav`,
  bytecode, `.zsav`, `.por`, XPORT 5 and 8, PSPP output) compared cell by
  cell with pyreadstat and pandas; 352 real `.sas7bdat` data sets from 13
  projects, the GSS 2021 release (4,032 x 943) and 590 generated files, all
  agreeing with pyreadstat; 9 sample catalogs and the GSS catalog, whose
  labels match the GSS Stata release for 941 of 942 variables. About
  124,000 truncated or mutated inputs, and 38,000 corrupted SAS files, gave
  only `statfiles` or `limit`.
- Timing for 10k rows by 20 variables: about 0.5 s for `.dta`, 0.6 to
  1.2 s for SPSS, 1.2 s for XPORT, 0.7 to 3.3 s for `.sas7bdat` (RDC
  slowest) and about 8 s for `.por`.

Not covered: files written by the vendors' own software are represented by
the third-party samples and real data sets above, not generated at test
time.

## Known limitations and open questions

- `.por` is slow: its base-30 digits are read one at a time.
- XPORT numbers are converted per cell; no `binary` primitive decodes IBM
  floats, so the bulk path of `.sas7bdat` does not apply.
- PSPP's `.por` writer keeps fewer digits than a double needs, so its
  `.por` and `.sav` values differ in the last digits; the deck reads what
  is written.

## Dependencies on the interpreter

- Floor `>=0.27.0`, the default binary only: the UTF-8 codecs of
  `encoding.encode` / `decode`, `strings.replicate` and
  `testing.assertThrowsArgs` arrived in 0.27.0.
- The `binary` number readers, bulk reads (`binary.readFloats`, `binary.readInts`) and
  the byte operations the `.sas7bdat` bulk decoder uses (0.26.0).
- `compress` (zlib), `encoding`, `decimal` and the bundled `csv` module.
- Caps as kind `"limit"` (`jennifer`'s M28.54, a reached cap is kind
  "limit").
