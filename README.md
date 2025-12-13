# simpleRevdepcheck


A lightweight helper to run reverse dependency checks for a package with
a small dependency graph. It downloads reverse deps from CRAN, installs
your local package, runs `R CMD check` on selected reverse deps, and
summarizes results.

## Installation

``` r
# install.packages("pak")
pak::pak("bcallaway11/simpleRevdepcheck")
```

## Example: check `ptetools` against local `did`

``` r
library(simpleRevdepcheck)

# Only check the reverse dep `ptetools` for the target package `did`
res <- simple_revdep_check(
  target_package = "did",
  reverse_deps = "ptetools",
  check_dir = ".simple_revdep"
)
res$summary
```

## Listing reverse dependencies

Use existing base tooling to list all reverse dependencies of a package:

``` r
# For the package in the current directory
pkg <- read.dcf("DESCRIPTION")[1, "Package"]
rev <- tools::package_dependencies(
  packages = pkg,
  reverse = TRUE
)
rev[[pkg]]
```

    NULL

Notes: - The function installs the local package from the current
directory first to ensure checks run against the latest local version. -
Results are saved to `.simple_revdep/check_results.rds`.
