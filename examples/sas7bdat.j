#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * sas7bdat example - read a SAS data set, attach the value labels of a
 * format catalog, and list the variables and the first rows with labels.
 *
 *   jennifer run examples/sas7bdat.j [data.sas7bdat [formats.sas7bcat]]
 *
 * Without arguments it reads a small built-in data set and its catalog.
 */

use binary;
use compress;
use encoding;
use fs;
use io;
use os;
use strings;

import "../src/statfiles.j" as statfiles;

# hadley.sas7bdat and formats.sas7bcat from the haven R package's tests
# (MIT licence, commit 66a332ab), gzip-compressed: a workshop survey whose
# variables workshop and gender carry the formats WORKSHOP and $GENDER.
def const SAMPLE_DATA as list of string init [
    "H4sIAAAAAAAC/+3dz2scVRwA8LfJ1qwYNIGF5lDoUCP0IJI0QSoUTWqiqUZTmoAKgoZka0J+bxJ7",
    "sqJXPaj0KnjwDxD04EUQL56KFDwoFOzBg/Tkqdo2zTqzO9PMbtMfKWIRPh+YfL/z5n3nvXnz2Bwn",
    "hB0/XP7g7a/L3T9991kpPPxj/8c9B7u6Dx0KAwOFtiPFm73aC03tA4XHB8KzIXS1F7Iek8OT0Qsn",
    "xkfHhkfGR9+I7tvI8NRwEpN7zn36xN8Dl38dzmJ9oHMXvt+JyfCFUMg9zzNP9Q329b/S//rTg28d",
    "PXlqItynZMze3176PDtarz+/sHU+P8cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADwP3R8Yet8ln94Jf7Ttj88FodoO4RLhUZ7Oc47",
    "0z6/b4XQl7ZvXQ/hjySJz7+K8/E0H4vzuTTvjPNjaf7LtRAG0/t8mctXc/mxXF7K5T9f3cm/aMnT",
    "2+f8+dydY3koOz8dNaSFQ7vHrK7rNnWlln6t9Vldaai5rqulX8t9LtRqWXvUVFe+zbzKt4y71FTX",
    "03K9PLR7fbml7sDQ7utXaqlvHS+6zTqU7zIeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPDf",
    "KIR2iwAAzc7GX+mO/0dGSWwrhFqLS2f7e5NuWQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "AIAHaft6rXZvPb8NvXuuORcO7rlmNf5e+F5rxvdUMxQ69rwGfaF0n+uWq4m/d94XLr6f5IfjoyM8",
    "En8ZPZvLvvio1bZr7fUrIRTDQ7narbj2zdx5fTbFQj1med/NvC105dp7cnmUyw/n8kzyTfahm2e9",
    "oS00Ztt4+qPpnMbS9sU0fpLGb9LYcCO+18XcedRiZHhqeHJq9OT8bAhnVqoL63Mrq69NnHp5cmzi",
    "5DuV5dlKNZ7Bi6OvjoyeCmv9IUzNVaL55fWN6ubMxko1OjO9Hp2pLC5Gq9XK6nS1Mrt25JY+MytL",
    "S5vL8zPTG5XZeue1gUafmZXN6nolWoovVOenF+s3m6ssrp7eXAxrgyFMvFupTi8uPhmdiE6vbC7P",
    "RhtxUTLJufWV1WhzvZJ0zL2ci/U3Flp21p11duy82+QNJGubxRtpWzFtK6bvppDulCxup20daVsS",
    "4615y968tkvb1dre9/C/4UosW6e/Yh/Fm6Y7Pe/uO1Q8mu3LVNY32a899ayxX5eLjTWpPaDnuJvj",
    "C1vn77Vv8kRtaXw0jV1p3J/G0p5GL9X3TEM5V9tZzw/c492K8cjJr0xvU+t7xabfoWb78if/AHsN",
    "wZMAAAIA"
];
def const SAMPLE_FORMATS as list of string init [
    "H4sIAAAAAAAC/+2bz2/TSBTHx40d0jaLEygqcGBHgLRcKCmpqiKBhMmPtmrcRHYXygVqUpcEmgaS",
    "UqVHxJULCImivewe9i/gwgVRrZC4dIUQXJBASBwQqrRLJX7dKB6PHTtu4qJiCwHvU43Gnsy88dfz",
    "Q/J7U4Qs/lm+nL/dFX1493oItT/ovbr910h0924UjzNtB9l6rQDTUB5n9sRJcSTAmDVkQcbp4Uwq",
    "nZVEYUzGGyUhjAmZ7CAmNrdcqf19cPmp8CIrTsa1XO/oxqPFek4eMIIQa9NzqCfWF+sVe8f7+04P",
    "5KQs2iCk71P/di+ayfn7u4W/avZnRADwnfDemLsEfQFHWBRAQzy5fMu/5J/w9/kFHt4TAAAAAAAA",
    "AAAAAKyHfFKWUrKEc4PHhsdEIdeqXpuWJgKRELmmvrMEHkyNJlNSa9ukzQCLglYbjE9kpRF5KOva",
    "T4RDej8fjO//P/8Y0V1n45nEEIwYJWK7YG0+EvL+XnNWPer43KeXt8FrA2yMZ2QpYJtL1cK87iM+",
    "8Dyj+7G7zPnDGEmvuNYXTkrtdtww2zD1uemPLtb2PNf+o3rMnJSRJbKkpVp9MWVjsVivkfq1FNN1",
    "UTvUUs1ow9XL612kv0bXl8YcTF280cHxzTTecGeX2KDrlVOXKSsWb9DFM9RSzWjD1cu/ja7Nxgb1",
    "8ONj8cbep8IOdmqU5ChM+14wkts8tNtx4fDGdUXRcFbECSVfULGsVuaKeXUdXb8EzLYDo1+jy7Lj",
    "h67t6JhSVbHQg8UePFWuaBJnleny2d+qrXSFWW/GK8z6qasbJaaLF86UlcokFvJ5tVrFojpbKE+2",
    "HK9Ozpvx6uT81LUVJcql0qWZYl6ZLZZncK5cma26zsOOoDfjZdrxa30Z89CYhr9LmXXWV/smb8bL",
    "suOHrm0oOT+jlIp5nNQWFk7V8gVl5qzqoisU8kaXZccPXTuc+0ayWD2Pp4rTarWFrk3t3uiy7Piz",
    "byQrxTkVi8oFrNB9o+S+bwQ7vNFl2fFD184143WpVJpvNmCmLq7TG12WHT90dTl1pURhOOO2b7Bh",
    "b3RZdvzQ1YHSYzls6HLlR/s++WiL/1sEGfqtscKfM15lCAEAAAAAAAAAAAAA8L2yYnz/TyyN2CIE",
    "y0bsbVWLOVL3wF56EAGjhmhfp+Yc2KcdPggake+1QSHLKGl6tMkTMNpfkDgZmrhsWL2V01U35fDJ",
    "NNYyzZQctThEXGPkWdNqSZlWtVBcu17AIpHc2rtlaIjuE2PKbzxSYQYFGV1+QA/M2uVHl/dfvnXz",
    "4hG7fOLfmkDNDhlEtPZM05MDLIo1cWXdW3Hkb1Y1nj2i99GFxlZmvujI75FGq/8X6H1oidMHkQyE",
    "hOjZkKD2XNq/cv1Ei4G8ESsQ+DYM2wMAAAAAAAAAAD8QnwEjKlURAEQAAA=="
];

/**
 * A built-in sample file.
 *
 * @param lines {list of string} its gzip-compressed base64 lines
 * @return {bytes} the file
 */
func sample(lines as list of string) {
    return compress.unpack("gzip", encoding.fromText("base64", strings.join($lines, "")));
}

def data as bytes;
def formats as bytes init binary.make(0);
if (len(os.ARGS) > 1) {
    $data = fs.readBytes(os.ARGS[1]);
    if (len(os.ARGS) > 2) {
        $formats = fs.readBytes(os.ARGS[2]);
    }
} else {
    $data = sample(SAMPLE_DATA);
    $formats = sample(SAMPLE_FORMATS);
}

def ds as statfiles.Dataset init statfiles.readSas7bdat($data, statfiles.options());
if (len($formats) > 0) {
    $ds = statfiles.withSasLabels($ds, statfiles.readSas7bcat($formats, statfiles.options()));
}
io.printf("data set %s, SAS %s, %s, %d rows\n", $ds.name, $ds.version, $ds.encoding, $ds.rowCount);
if ($ds.label != "") {
    io.printf("  label: %s\n", $ds.label);
}
for (def v in $ds.variables) {
    io.printf(
        "  %s|pad=10|align=left %s|pad=8|align=left %s|pad=10|align=left %d labels  %s\n",
        $v.name,
        $v.type,
        $v.format,
        len($v.valueLabels),
        $v.label);
}
for (def r in 0..$ds.rowCount) {
    if ($r == 5) {
        io.printf("  ...\n");
        break;
    }
    def cells as list of string init [];
    for (def name in statfiles.names($ds)) {
        def cell as string init statfiles.text($ds, $name, $r);
        def label as string init statfiles.labelOf($ds, $name, $r);
        if ($label != "") {
            $cell = $cell + " (" + $label + ")";
        }
        $cells[] = $cell;
    }
    io.printf("  %s\n", strings.join($cells, " | "));
}
