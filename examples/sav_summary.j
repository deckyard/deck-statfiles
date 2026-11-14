#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * Summarise an SPSS .sav or .zsav file: its variables, then the mean of a
 * numeric variable over the cells that are not missing, and how often each
 * value label occurs.
 *
 *   jennifer run examples/sav_summary.j [file.sav] [variable]
 *
 * Without arguments it reads examples/sav_survey.sav and its `income` and
 * `sex` variables.
 */

use fs;
use io;
use maps;
use os;
use stats;

import "../src/statfiles.j" as statfiles;

def path as string init "examples/sav_survey.sav";
def target as string init "income";
if (len(os.ARGS) > 1) {
    $path = os.ARGS[1];
}
if (len(os.ARGS) > 2) {
    $target = os.ARGS[2];
}

def ds as statfiles.Dataset init statfiles.read(fs.readBytes($path));
io.printf("%s (%s, %s): %d rows\n", $ds.label, $ds.format, $ds.encoding, $ds.rowCount);
for (def v in $ds.variables) {
    io.printf("  %s|pad=10 %s|pad=7 %s|pad=8 %s\n", $v.name, $v.type, $v.format, $v.label);
}

def values as list of float init statfiles.present($ds, $target);
io.printf(
    "mean %s over %d of %d rows: %f|prec=2\n",
    $target,
    len($values),
    $ds.rowCount,
    stats.mean($values));

# a value SPSS declares missing keeps its value, with the code "user"
def age as int init statfiles.indexOf($ds, "age");
if ($age >= 0) {
    for (def r in 0..$ds.rowCount) {
        if ($ds.missing[$age][$r] != "") {
            io.printf("age in row %d is missing (%s)\n", $r, $ds.missing[$age][$r]);
        }
    }
}

if (statfiles.indexOf($ds, "sex") >= 0) {
    def counts as map of string to int init {};
    for (def r in 0..$ds.rowCount) {
        def label as string init statfiles.labelOf($ds, "sex", $r);
        if (not maps.has($counts, $label)) {
            $counts[$label] = 0;
        }
        $counts[$label] = $counts[$label] + 1;
    }
    io.printf("sex: %v\n", $counts);
}
