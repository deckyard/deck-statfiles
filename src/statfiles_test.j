# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests: jennifer test src/statfiles_test.j
 *
 * The topic overlays are fragments spliced in here, not standalone suites.
 * Sample files are constants in src/topics/fixtures/, written once by
 * pyreadstat and PSPP, so the overlays run from a copy of src/ alone.
 */
use testing;

include "topics/dataset_test.j";
include "topics/dta_test.j";
include "topics/sav_test.j";
include "topics/por_test.j";
include "topics/xpt_test.j";
include "topics/sas7bdat_test.j";
include "topics/sas7bcat_test.j";
