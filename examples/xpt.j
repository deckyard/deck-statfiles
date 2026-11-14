#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * xpt example - list every member of a SAS XPORT file with its variables
 * and its first rows.
 *
 *   jennifer run examples/xpt.j [file.xpt]
 *
 * Without an argument it reads a small built-in sample of two members.
 */

use encoding;
use fs;
use io;
use os;
use strings;

import "../src/statfiles.j" as statfiles;

# A version 5 file of two members, FIRST and SECOND, written by pyreadstat.
def const SAMPLE as list of string init [
    "SEVBREVSIFJFQ09SRCoqKioqKipMSUJSQVJZIEhFQURFUiBSRUNPUkQhISEhISEhMDAwMDAwMDAw",
    "MDAwMDAwMDAwMDAwMDAwMDAwMDAwICBTQVMgICAgIFNBUyAgICAgU0FTTElCICA2LjA2ICAgIGJz",
    "ZDQuMiAgICAgICAgICAgICAgICAgICAgICAgICAgMTROT1YyNjoxNDo1MjowMzE0Tk9WMjY6MTQ6",
    "NTI6MDMgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
    "ICAgICAgICAgICAgSEVBREVSIFJFQ09SRCoqKioqKipNRU1CRVIgIEhFQURFUiBSRUNPUkQhISEh",
    "ISEhMDAwMDAwMDAwMDAwMDAwMDAxNjAwMDAwMDAwMTQwICBIRUFERVIgUkVDT1JEKioqKioqKkRT",
    "Q1JQVFIgSEVBREVSIFJFQ09SRCEhISEhISEwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAg",
    "IFNBUyAgICAgRklSU1QgICBTQVNEQVRBIDYuMDYgICAgYnNkNC4yICAgICAgICAgICAgICAgICAg",
    "ICAgICAgICAxNE5PVjI2OjE0OjUyOjAzMTROT1YyNjoxNDo1MjowMyAgICAgICAgICAgICAgICBG",
    "aXJzdCBtZW1iZXIgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBIRUFERVIgUkVD",
    "T1JEKioqKioqKk5BTUVTVFIgSEVBREVSIFJFQ09SRCEhISEhISEwMDAwMDAwMDAxMDAwMDAwMDAw",
    "MDAwMDAwMDAwMDAgIAABAAAACAABeCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
    "ICAgICAgICAgICAgICAgICAgICAAAAAAAAEAACAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAICAgICAgICAgICAgICAgICAg",
    "ICBIRUFERVIgUkVDT1JEKioqKioqKk9CUyAgICAgSEVBREVSIFJFQ09SRCEhISEhISEwMDAwMDAw",
    "MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAgIEEQAAAAAAAAQSAAAAAAAABBMAAAAAAAACAgICAgICAg",
    "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgSEVBREVSIFJF",
    "Q09SRCoqKioqKipNRU1CRVIgIEhFQURFUiBSRUNPUkQhISEhISEhMDAwMDAwMDAwMDAwMDAwMDAx",
    "NjAwMDAwMDAwMTQwICBIRUFERVIgUkVDT1JEKioqKioqKkRTQ1JQVFIgSEVBREVSIFJFQ09SRCEh",
    "ISEhISEwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAgIFNBUyAgICAgU0VDT05EICBTQVNE",
    "QVRBIDYuMDYgICAgYnNkNC4yICAgICAgICAgICAgICAgICAgICAgICAgICAxNE5PVjI2OjE0OjUy",
    "OjAzMTROT1YyNjoxNDo1MjowMyAgICAgICAgICAgICAgICBTZWNvbmQgbWVtYmVyICAgICAgICAg",
    "ICAgICAgICAgICAgICAgICAgICAgICAgICBIRUFERVIgUkVDT1JEKioqKioqKk5BTUVTVFIgSEVB",
    "REVSIFJFQ09SRCEhISEhISEwMDAwMDAwMDAyMDAwMDAwMDAwMDAwMDAwMDAwMDAgIAACAAAAAwAB",
    "eSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAA",
    "AAAAAAAAACAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAIAAJ6ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
    "ICAgICAgICAgICAgICAgICAgICAgICAgIAAAAAAAAQAAICAgICAgICAAAAAAAAAAAwAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgICAgICAgICAgICAg",
    "ICAgICAgICAgICAgICAgICAgICAgICAgICAgSEVBREVSIFJFQ09SRCoqKioqKipPQlMgICAgIEhF",
    "QURFUiBSRUNPUkQhISEhISEhMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwICBvbmVBqAAA",
    "AAAAAHR3by4AAAAAAAAAICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
    "ICAgICAgICAgICAgICAgIA=="
];

def data as bytes;
if (len(os.ARGS) > 1) {
    $data = fs.readBytes(os.ARGS[1]);
} else {
    $data = encoding.fromText("base64", strings.join(SAMPLE, ""));
}

for (def ds in statfiles.readXptMembers($data, statfiles.options())) {
    io.printf(
        "member %s (%s), XPORT version %s, %d rows\n",
        $ds.name,
        $ds.label,
        $ds.version,
        $ds.rowCount);
    for (def v in $ds.variables) {
        io.printf(
            "  %s|pad=20|align=left %s|pad=8|align=left %s|pad=12|align=left %s\n",
            $v.name,
            $v.type,
            $v.format,
            $v.label);
    }
    for (def r in 0..$ds.rowCount) {
        if ($r == 5) {
            io.printf("  ...\n");
            break;
        }
        def cells as list of string init [];
        for (def name in statfiles.names($ds)) {
            $cells[] = statfiles.text($ds, $name, $r);
        }
        io.printf("  %s\n", strings.join($cells, " | "));
    }
}
