<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Stata .dta

`readDta` reads Stata datasets of every released format from 104 to 119 (Stata 15 and later, more than 32,767 variables), in either byte
order. `read` and `readWith` detect the format and call it for you.

```jennifer
import "@deckyard/statfiles/" as statfiles;

def ds as statfiles.Dataset init statfiles.read(fs.readBytes("auto.dta"));
io.printf("format %s, %d rows\n", $ds.version, $ds.rowCount);
io.printf("mean price %v\n", stats.mean(statfiles.present($ds, "price")));
```

`statfiles.readDta(data, statfiles.options())` does the same without the
detection. A file that is not a `.dta` throws there.

## Formats

| Format | Stata | Layout |
| --- | --- | --- |
| 104, 105 | before 6 | fixed header, 8-character names, old value labels (2-byte values, 8-byte texts) |
| 108 | 6 | 81-byte labels, value label tables, 8-character label names |
| 110, 111 | 7, 7 SE | 32-character names; 111 has the type codes of 113 |
| 113 | 8, 9 | extended missing values `.a` to `.z` |
| 114, 115 | 10 to 12 | 48-character formats |
| 117 | 13 | tagged sections (`<stata_dta>`), `strL` |
| 118 | 14 to 19 | UTF-8; names of 32 characters in 129 bytes, labels of 80 in 321 |
| 119 | 15 to 19 | 4-byte variable count, more than 32,767 variables |

Formats 106, 107, 109, 112 and 116 were never released and are refused.

## What maps to what

| Stata | `Dataset` / `Variable` |
| --- | --- |
| release number | `version`, as text (`"118"`); `format` is `"dta"` |
| dataset label | `label` |
| variable name, label, display format | `name`, `label`, `format` (such as `%9.0g`, `%td`) |
| `byte`, `int`, `long`, `float`, `double` | `type` `"numeric"`, `storage` the Stata type, `width` its size (1, 2, 4, 4, 8 bytes), values in `numbers[i]` |
| `str1` to `str2045` | `type` `"string"`, `storage` `str<n>`, `width` n bytes, values in `texts[i]` |
| `strL` | `type` `"string"`, `storage` `strL`, `width` 0 |
| value label attached to a variable | `valueLabels`, keyed by `valueKey` of the value |

A `float` keeps its single-precision value (`1.1` reads as
`1.100000023841858`). Display formats are returned as written; dates stay
numbers (days or milliseconds since 1960-01-01, as the format says).
String values keep their trailing blanks (`"a "` reads as `"a "`, as in
pandas and ReadStat): a `str<n>` value ends at its first NUL or the
field's end, and a strL is read as stored (an ASCII strL without its
closing NUL). Variable and value labels lose trailing blanks.
`missingValues` and `missingRange` stay
empty: Stata has no declared missing values. Characteristics, notes, the
sort order and the timestamp are skipped.

## Missing values

Stata stores a missing number as a value above the type's largest valid one.
`missing[i][row]` holds its code and `numbers[i][row]` is `0.0`.

| Type | Largest valid value | Missing values |
| --- | --- | --- |
| `byte` | 100 | 101 (`.`) to 127 (`.z`) |
| `int` | 32,740 | 32,741 to 32,767 |
| `long` | 2,147,483,620 | 2,147,483,621 to 2,147,483,647 |
| `float` | about 1.701e+38 (`0x7effffff`) | `0x7f000000` (`.`), each further code `0x800` higher |
| `double` | about 8.988e+307 (`0x7fdfffffffffffff`) | `0x7fe0000000000000` (`.`), each code `0x010000000000` higher |

A float or double between two codes takes the lower one, as Stata does; one
above `.z`, a NaN or an infinity is an error. Before format 113 there is only
`.`: the type's largest value (127, 32,767, 2,147,483,647, 2^127, 2^1023),
and in formats 104 and 105 also the double 2^333.

A value label on an extended missing value is keyed by its code, so
`labelOf` finds it for a missing cell:

```jennifer
io.printf("%s\n", statfiles.missingCode($ds, "income", 3));   # .a
io.printf("%s\n", statfiles.labelOf($ds, "income", 3));       # refused
```

## Encodings

Formats 118 and 119 are UTF-8. Older files are in the character set of the
machine that wrote them, most often Windows-1252, the default here (as in
pandas and ReadStat). `Options.encoding` overrides both, and `Dataset.encoding`
reports the one used:

```jennifer
def opts as statfiles.Options init statfiles.options();
$opts.encoding = "iso-8859-1";
def ds as statfiles.Dataset init statfiles.readWith(fs.readBytes("old.dta"), $opts);
```

Text that is not valid in the character set (a UTF-8 file read as ASCII, a
Latin-1 file read as UTF-8) is an error, not a replacement character. A
binary `strL` is decoded like text too.

## Limits and errors

A file is refused whose rows times variables exceed
`Options.maxCells` (default `DEFAULT_MAX_CELLS`) with kind `"limit"`, before
anything is allocated. Everything else that is wrong throws kind
`"statfiles"`:

- a truncated file, including an old-format file that ends inside its data
  or inside a value label table (one that ends after its data or between
  two tables is complete)
- an unknown format, byte order or variable type
- a tagged file whose sections are not where its map says, a missing tag,
  bytes after `</stata_dta>`
- a `strL` reference no `GSO` record defines, a `GSO` of an unknown type or
  defined twice
- a value label table whose sizes disagree or whose text offset lies outside
  it

Numeric columns are read in bulk, one call per column; reading 10,000 rows of
20 variables (16 numeric, 4 string) takes about 0.5 s, most of it in the
string columns.
