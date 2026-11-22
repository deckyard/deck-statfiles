#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * Describe a Stata .dta file: jennifer run examples/dta_describe.j [file.dta]
 *
 * Prints the dataset label, each variable with its storage type, label and
 * value labels, the mean of every numeric variable over its present values,
 * and the table as CSV with value labels applied. Without an argument it
 * reads a small embedded sample (format 113, written by pyreadstat).
 */

use encoding;
use fs;
use io;
use maps;
use os;
use stats;
use strings;

import "../src/statfiles.j" as statfiles;

def const SAMPLE as list of string init [
    "cQIBAAMAAwAAAHYxMTMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADE0IE5vdiAyMDI2IDE1OjAwAP3/BGlk",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHNjb3JlAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAG5hbWUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJTEyLjBnAAAA",
    "AAAAJTEwLjBnAAAAAAAAJS05cwAAAAAAAAAAaWQwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAA4D9hbm4AAgAAAAAAAAAA",
    "AOB/Ym9iAAMAAAAAAAAAAAAAQGNhcmwkAAAAaWQwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAgAAAAwAAAAAAAAABgAAAAEAAAADAAAAZmlyc3QAdGhpcmQA"
];

def data as bytes;
if (len(os.ARGS) > 1) {
    $data = fs.readBytes(os.ARGS[1]);
} else {
    $data = encoding.fromText("base64", strings.join(SAMPLE, ""));
}

def ds as statfiles.Dataset init statfiles.read($data);
io.printf(
    "Stata format %s, %d rows, label \"%s\", text in %s\n",
    $ds.version,
    $ds.rowCount,
    $ds.label,
    $ds.encoding);
for (def v in $ds.variables) {
    io.printf("%s\t%s\t%s\t%s\n", $v.name, $v.storage, $v.format, $v.label);
    for (def key in maps.keys($v.valueLabels)) {
        io.printf("    %s = %s\n", $key, $v.valueLabels[$key]);
    }
    if ($v.type == "numeric") {
        def xs as list of float init statfiles.present($ds, $v.name);
        if (len($xs) > 0) {
            io.printf("    mean %v over %d of %d rows\n", stats.mean($xs), len($xs), $ds.rowCount);
        }
    }
}
io.printf("%s\n", statfiles.toCsv($ds, true));
