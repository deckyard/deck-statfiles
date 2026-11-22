#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * Print an SPSS portable .por file as CSV, with value labels in place of
 * the values that have one.
 *
 *   jennifer run examples/por_summary.j [file.por]
 *
 * Without an argument it reads examples/por_survey.por (written by PSPP).
 */

use fs;
use io;
use os;

import "../src/statfiles.j" as statfiles;

def path as string init "examples/por_survey.por";
if (len(os.ARGS) > 1) {
    $path = os.ARGS[1];
}

def ds as statfiles.Dataset init statfiles.read(fs.readBytes($path));
io.printf("%d variables, %d rows\n", len($ds.variables), $ds.rowCount);
for (def v in $ds.variables) {
    if (len($v.missingValues) > 0) {
        io.printf("%s declares missing: %v\n", $v.name, $v.missingValues);
    }
}
io.printf("%s\n", statfiles.toCsv($ds, true));
