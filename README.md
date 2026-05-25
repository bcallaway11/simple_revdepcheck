# revdeplite


A lightweight alternative to the
[`revdepcheck`](https://github.com/r-lib/revdepcheck) package for
running reverse dependency checks. The key advantage is speed: rather
than building isolated libraries from scratch, `revdeplite` uses
packages that are already installed locally, making checks dramatically
faster when most dependencies are already present. It installs your
local package, upgrades only what is missing or outdated, and runs
`R CMD check` on each reverse dependency. It also supports checking
GitHub development versions of packages alongside CRAN releases.

## Installation

``` r
# install.packages("pak")
pak::pak("bcallaway11/revdeplite")
```

## Basic usage: CRAN reverse dependencies only

Run from the root of the package you are preparing to release. The
function auto-detects the package name from `DESCRIPTION`, installs the
local version, discovers all CRAN reverse dependencies, and checks them.

``` r
library(revdeplite)

# Run from the package root (e.g., ~/Dropbox/BMisc)
res <- revdeplite(num_cores = 4)
```

Results are printed to the console and saved to `.revdeplite/`. A
markdown report is written to `.revdeplite/revdeplite-results.md` after
each run.

## Adding GitHub development versions

Use `github_deps` to also check the current GitHub versions of packages
that have already been updated to work with your new release. Each repo
is cloned with `git clone --depth=1` and checked alongside the CRAN
packages. The summary `Source` column distinguishes `"cran"` from
`"github"` results.

``` r
res <- revdeplite(
  github_deps = c(
    "bcallaway11/did",
    "pedrohcgs/DRDID",
    "bcallaway11/ptetools"
  ),
  num_cores = 4
)
```

This is useful when submitting to CRAN: you can demonstrate to reviewers
that the updated GitHub versions of reverse dependencies pass cleanly
alongside the current CRAN versions.

## Summary functions

After a run, `print_revdep_summary()` prints separate tables for CRAN
and GitHub packages:

``` r
print_revdep_summary(res$summary)
#>
#> === CRAN Packages ===
#>    Package Errors Warnings Notes Status
#>        did      0        0     0   PASS
#>      DRDID      0        1     0   WARN
#>   ptetools      0        1     0   WARN
#>
#> === GitHub Packages ===
#>    Package Errors Warnings Notes Status
#>        did      0        0     0   PASS
#>      DRDID      0        0     0   PASS
#>   ptetools      0        0     0   PASS
```

## Worked example: preparing BMisc for a breaking release

The `BMisc` package renamed a set of legacy function names (e.g.,
`makeBalancedPanel` → `make_balanced_panel`, `rhs.vars` → `rhs_vars`) in
version 1.4.9. Before submitting to CRAN, the goal is to confirm that
(1) the current CRAN versions of reverse dependencies only produce
deprecation *warnings* — not errors — and (2) the updated GitHub
versions pass cleanly.

**Step 1: baseline check against CRAN versions**

``` r
setwd("~/Dropbox/BMisc")
library(revdeplite)

res_cran <- revdeplite(num_cores = 4)
print_revdep_summary(res_cran$summary)
#>
#> === CRAN Packages ===
#>     Package Errors Warnings Notes Status
#>        cdid      0        0     0   PASS
#>     contdid      0        0     0   PASS
#>         did      0        0     0   PASS
#>       DRDID      0        1     0   WARN
#>     fastdid      0        0     0   PASS
#>    ptetools      0        1     0   WARN
#>         qte      0        1     0   WARN
#>  triplediff      0        1     0   WARN
```

The warnings are the expected deprecation warnings from calling the old
function names. No errors means no package *breaks* — the deprecated
functions are still present in this release.

**Step 2: confirm GitHub fixes pass cleanly**

``` r
res_both <- revdeplite(
  github_deps = c(
    "bcallaway11/did",
    "pedrohcgs/DRDID",
    "bcallaway11/ptetools",
    "bcallaway11/qte"
  ),
  num_cores = 4
)
print_revdep_summary(res_both$summary)
#>
#> === CRAN Packages ===
#>     Package Errors Warnings Notes Status
#>        cdid      0        0     0   PASS
#>     contdid      0        0     0   PASS
#>         did      0        0     0   PASS
#>       DRDID      0        1     0   WARN
#>    ptetools      0        1     0   WARN
#>         qte      0        1     0   WARN
#>  triplediff      0        1     0   WARN
#>
#> === GitHub Packages ===
#>   Package Errors Warnings Notes Status
#>       did      0        0     0   PASS
#>     DRDID      0        0     0   PASS
#>  ptetools      0        0     0   PASS
#>       qte      0        0     0   PASS
```

The `github` rows confirm that updated packages pass without deprecation
warnings. This output, along with the markdown report in
`.revdeplite/revdeplite-results.md`, can be shared with CRAN reviewers.

## Checking a specific subset of reverse dependencies

``` r
# Only check two packages instead of all reverse dependencies
res <- revdeplite(
  reverse_deps = c("did", "ptetools"),
  num_cores = 2
)
```

## Re-printing saved results

Results are saved to `.revdeplite/check_results.rds` and a markdown
report to `.revdeplite/revdeplite-results.md` after each run. They can
be re-displayed without re-running the checks:

``` r
print_revdep_results()
```

## Notes

- Requires `git` on `PATH` when using `github_deps`.
- Uses `pak` for dependency installation if available (faster, smarter
  about skipping already-installed packages); falls back to
  `install.packages()` otherwise.
- `_R_CHECK_FORCE_SUGGESTS_=false` is set during checks so missing
  `Suggests` packages do not cause failures.
- `_R_CHECK_SYSTEM_CLOCK_=false` suppresses the “unable to verify
  current time” NOTE that appears in offline or sandboxed environments.
- Stale CRAN tarballs from previous runs are removed automatically at
  the start of each run; GitHub clones are updated via `git pull` rather
  than re-cloned.
- Results include a `Source` column (`"cran"` or `"github"`) in the
  summary data frame and in the detailed printed output.
