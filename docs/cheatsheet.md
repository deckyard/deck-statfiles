<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# statfiles cheatsheet

Every export of `@deckyard/statfiles`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/statfiles/" as statfiles;
```

A reader takes the file as `bytes` (`fs.readBytes`) and returns a
`Dataset`. A malformed file or a bad argument throws
`Error{kind: "statfiles"}`; a file over a cap (`Options.maxCells`, the
unpacked size of compressed SPSS cases or of a compressed `.sas7bdat`) is kind
`"limit"`. A `name` is a variable's
name exactly as stored; a `row` counts from 0.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `VERSION` | `"0.1.0"` | this deck's version |
| `ERROR_KIND` | `"statfiles"` | the kind of a malformed file or a bad argument |
| `DEFAULT_MAX_CELLS` | `20000000` | the most cells (rows times variables) read |
| `DEFAULT_MAX_BYTES` | `268435456` | the most bytes compressed SPSS cases or the rows of a compressed `.sas7bdat` unpack to |
| `MISSING_SYSTEM` | `"."` | the code of a system-missing cell |
| `MISSING_USER` | `"user"` | the code of a value SPSS declares missing |
| `LOWEST` | `-1.7976931348623157e308` | an SPSS missing range's open low end (`LO`) |
| `HIGHEST` | `1.7976931348623157e308` | an SPSS missing range's open high end (`HI`) |

## Reading

| Function | Returns | Does |
|---|---|---|
| `read(data)` | `Dataset` | detect the format and read it with the default options |
| `readWith(data, opts)` | `Dataset` | the same with `Options` |
| `options()` | `Options` | the defaults: the file's own encoding, `DEFAULT_MAX_CELLS`, `DEFAULT_MAX_BYTES` |
| `detect(data)` | `string` | `dta`, `sav`, `zsav`, `por`, `xpt`, `sas7bdat`, `sas7bcat` (a catalog, which `read` refuses), or `""` for none of them |
| `readDta(data, opts)` | `Dataset` | Stata `.dta`, formats 104 to 119, either byte order |
| `readSav(data, opts)` | `Dataset` | SPSS `.sav` (uncompressed or bytecode compressed, either byte order) or `.zsav` |
| `readPor(data, opts)` | `Dataset` | SPSS portable `.por`, through its translation table |
| `readXpt(data, opts)` | `Dataset` | SAS XPORT `.xpt`, version 5 or 8, of one member; several members are an error |
| `readXptMembers(data, opts)` | `list of Dataset` | every member of an XPORT file; `maxCells` caps them together |
| `readSas7bdat(data, opts)` | `Dataset` | SAS `.sas7bdat`: 32- or 64-bit, either byte order, uncompressed, RLE or RDC; deleted rows left out |

## SAS value labels

| Function | Returns | Does |
|---|---|---|
| `readSas7bcat(data, opts)` | `map of string to map of string to string` | the value labels of a SAS format catalog (`.sas7bcat`): format name (`GENDER`, `$GENDER`) to value to label |
| `withSasLabels(ds, catalog)` | `Dataset` | `ds` with each variable's `valueLabels` from the catalog format its `format` names |
| `sasFormatName(format)` | `string` | a display format's catalog name: `$GENDER6.` is `$GENDER`, `8.2` is `""` |

## Cells and columns

| Function | Returns | Does |
|---|---|---|
| `names(ds)` | `list of string` | the variable names, in file order |
| `indexOf(ds, name)` | `int` | a variable's index, -1 if there is none |
| `variable(ds, name)` | `Variable` | one variable |
| `column(ds, name)` | `list of float` | every value of a numeric variable; a missing cell is an error |
| `present(ds, name)` | `list of float` | the values that are not missing, in row order |
| `textColumn(ds, name)` | `list of string` | every value of a string variable |
| `number(ds, name, row)` | `float` | one numeric cell; an SPSS user-missing value is returned, any other missing cell is an error |
| `text(ds, name, row)` | `string` | one cell as text; a missing number as its code |
| `missingCode(ds, name, row)` | `string` | `""`, `.`, `.a` to `.z`, `._` or `user` |
| `isMissing(ds, name, row)` | `bool` | the cell is missing, for any reason |
| `labelOf(ds, name, row)` | `string` | the cell's value label, `""` if none |
| `valueKey(x)` | `string` | a number as value labels are keyed: `3`, `-1`, `2.5` |
| `toCsv(ds, labels)` | `string` | the dataset as CSV, a missing number empty; `labels` writes value labels instead of values |

## Types

### `Dataset`

| Field | Meaning |
|---|---|
| `format as string` | `dta`, `sav`, `zsav`, `por`, `xpt` or `sas7bdat` |
| `version as string` | Stata's format (`118`), XPORT's `5` or `8`, the SAS release (`9.0401M5`), `""` for SPSS |
| `name as string` | an XPORT member's or SAS data set's name, else `""` |
| `label as string` | the dataset's label, `""` if none |
| `encoding as string` | the character set the text was decoded from |
| `rowCount as int` | the number of rows |
| `variables as list of Variable` | the variables, in file order |
| `numbers as list of list of float` | a numeric variable's values by row (0.0 where missing); `[]` for a string variable |
| `texts as list of list of string` | a string variable's values by row; `[]` for a numeric variable |
| `missing as list of list of string` | each cell's missing code, `""` when present |

### `Variable`

| Field | Meaning |
|---|---|
| `name as string` | the name, as stored |
| `label as string` | its label, `""` if none |
| `type as string` | `numeric` or `string` |
| `storage as string` | the file's type: Stata `byte` ... `double`, `str<n>`, `strL`; SPSS and SAS `numeric` / `string` |
| `width as int` | a string variable's width in bytes; 0 for a number |
| `format as string` | the display format: `%9.0g`, `F8.2`, `DATE9.` |
| `valueLabels as map of string to string` | value labels, keyed by `valueKey` (Stata `.a` keyed `".a"`) |
| `missingValues as list of string` | values SPSS declares missing, as `valueKey` writes them |
| `missingRange as list of float` | an SPSS missing range `[low, high]`, or `[]` |

### `Options`

| Field | Meaning |
|---|---|
| `encoding as string` | the text's character set, overriding the file's; `""` for the file's own |
| `maxCells as int` | the most cells read; kind `"limit"` beyond |
| `maxBytes as int` | the most bytes compressed SPSS cases (`.zsav` zlib blocks, and bytecode in the uncompressed layout) or the rows of a compressed `.sas7bdat` unpack to; kind `"limit"` beyond |
