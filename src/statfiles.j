# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * Readers for the data files of SPSS, Stata and SAS: Stata `.dta`
 * (formats 104 to 119), SPSS `.sav`, `.zsav` and `.por`, SAS XPORT `.xpt`
 * (versions 5 and 8) and SAS `.sas7bdat`, with value labels from a
 * `.sas7bcat` catalog. Read-only; nothing is written.
 *
 * Every reader returns one `Dataset`: the variables with their names,
 * labels, display formats, value labels and declared missing values, and
 * the cells stored by column. A numeric cell is a `float`, a string cell a
 * `string`; a missing cell has a missing code (`.`, `.a` to `.z`, `._`, or
 * `user` for a value SPSS declares missing). `column` hands a variable to
 * `stats` or `linalg`, `toCsv` writes the whole table.
 *
 * The readers work on `bytes` and need no capability: read the file with
 * `fs.readBytes` first. A malformed file throws `Error{kind: "statfiles"}`;
 * a file over a cap (`Options.maxCells`, the unpacked size of compressed
 * SPSS cases or `.sas7bdat` rows) throws kind `"limit"`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `dataset` | `Dataset`, `Variable`, `Options`, `read`, format detection, cells, columns, `toCsv` |
 * | `dta` | Stata `.dta` |
 * | `sav` | SPSS `.sav` and `.zsav` |
 * | `por` | SPSS portable `.por` |
 * | `xpt` | SAS XPORT `.xpt` |
 * | `sas7bdat` | SAS `.sas7bdat` |
 * | `sas7bcat` | SAS `.sas7bcat` value labels, `withSasLabels` |
 *
 * @module statfiles
 * @see https://www.stata.com/help.cgi?dta
 * @see https://www.gnu.org/software/pspp/pspp-dev/html_node/System-File-Format.html
 * @example
 *   def ds as statfiles.Dataset init statfiles.read(fs.readBytes("survey.sav"));
 *   io.printf("%d rows\n", $ds.rowCount);
 *   io.printf("mean age %f\n", stats.mean(statfiles.present($ds, "age")));
 */
use binary;
use compress;
use convert;
use decimal;
use encoding;
use io;
use lists;
use maps;
use math;
use regex;
use strings;

import "csv.j" as csv;

include "topics/dataset.j";
include "topics/dta.j";
include "topics/sav.j";
include "topics/por.j";
include "topics/xpt.j";
include "topics/sas7bdat.j";
include "topics/sas7bcat.j";
