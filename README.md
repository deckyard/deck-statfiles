# @deckyard/statfiles

[![test](https://github.com/deckyard/deck-statfiles/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-statfiles/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-statfiles/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-statfiles)](https://github.com/deckyard/deck-statfiles/releases/latest)

Readers for the data files of SPSS™, Stata™ and SAS™, for
[Jennifer](https://jennifer-lang.dev/) programs: Stata `.dta` (formats
104 to 119), SPSS `.sav`, `.zsav` and portable `.por`, SAS XPORT `.xpt`
(versions 5 and 8), and SAS data sets `.sas7bdat` with the value labels
of `.sas7bcat` format catalogs. Every reader returns one `Dataset`: the
variables with their labels, display formats, value labels and declared
missing values, and the cells by column, ready for `stats` and `linalg` or
as CSV. Read-only.

**[Documentation](https://deckyard.github.io/deck-statfiles/)**

## Install

```sh
jvc add @deckyard/statfiles
```

This vendors the deck to `vendor/<scope>/statfiles/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-statfiles-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/statfiles/" as statfiles;

def ds as statfiles.Dataset init statfiles.read(fs.readBytes("survey.sav"));
io.printf("%d rows, mean age %.1f\n", $ds.rowCount, stats.mean(statfiles.present($ds, "age")));
fs.writeString("survey.csv", statfiles.toCsv($ds, true));
```

`examples/` has one program per format: `dta_describe.j`, `sav_summary.j`,
`por_summary.j`, `xpt.j` and `sas7bdat.j`.

## Requirements

Jennifer 0.28.0 or newer. No capability: the readers take the file as
`bytes`, so reading it from disk is the caller's.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/statfiles_test.j   # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.

## Trademarks

SAS™ is a trademark of SAS Institute Inc. SPSS™ and IBM™ are trademarks of
International Business Machines Corporation. Stata™ is a trademark of
StataCorp LLC. Other product and company names may be trademarks of their
respective owners. They are used only to identify the products this deck
works with. This deck is an independent project, not affiliated with,
sponsored or endorsed by SAS Institute Inc., International Business Machines
Corporation or StataCorp LLC.
