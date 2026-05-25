# simple_revdepcheck


A lightweight alternative to the `revdepcheck` package for running
reverse dependency checks when most dependencies are already installed
locally. Instead of building isolated temporary libraries from scratch,
it installs your local package, upgrades only what is missing or
outdated, and runs `R CMD check` on each reverse dependency. It also
supports checking GitHub development versions of packages alongside CRAN
releases.

## Installation

``` r
# install.packages("pak")
pak::pak("bcallaway11/simple_revdepcheck")
```

## Basic usage: CRAN reverse dependencies only

Run from the root of the package you are preparing to release. The
function auto-detects the package name from `DESCRIPTION`, installs the
local version, discovers all CRAN reverse dependencies, and checks them.

``` r
library(simpleRevdepcheck)

# Run from the package root (e.g., ~/Dropbox/BMisc)
res <- simple_revdep_check(num_cores = 4)
res$summary
```

## Adding GitHub development versions

Use `github_deps` to also check the current GitHub versions of packages
that have already been updated to work with your new release. Each repo
is cloned with `git clone --depth=1` and checked alongside the CRAN
packages. The summary `Source` column distinguishes `"cran"` from
`"github"` results.

``` r
res <- simple_revdep_check(
  github_deps = c(
    "bcallaway11/did",
    "bcallaway11/csabounds",
    "pedrohcgs/DRDID",
    "bcallaway11/ptetools"
  ),
  num_cores = 4
)
res$summary
#>      Package  Source Errors Warnings Notes Status
#> 1        did    cran      0        0     1   NOTE
#> 2        did  github      0        0     1   NOTE
#> 3  csabounds    cran      0        0     0   PASS
#> ...
```

This is useful when submitting to CRAN: you can demonstrate to reviewers
that both the current CRAN versions and the updated GitHub versions of
reverse dependencies pass cleanly.

## Checking a specific subset of reverse dependencies

``` r
# Only check two packages instead of all reverse dependencies
res <- simple_revdep_check(
  reverse_deps = c("did", "ptetools"),
  num_cores = 2
)
```

## Re-printing saved results

Results are saved to `.simple_revdep/check_results.rds` after each run
and can be re-displayed without re-running the checks:

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
- Results include a `Source` column (`"cran"` or `"github"`) in the
  summary data frame and in the detailed printed output.
