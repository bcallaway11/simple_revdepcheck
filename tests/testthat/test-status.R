test_that("simple_revdep_check accepts target_package first and reverse_deps (smoke)", {
    dir <- tempfile("revdepcheck-")
    expect_error(
        simple_revdep_check(
            target_package = "did",
            reverse_deps = "ptetools",
            check_dir = dir,
            check_args = c("--no-manual", "--no-tests"),
            build_args = "--no-build-vignettes",
            quiet = TRUE
        ),
        NA
    )
})
test_that("revdep_status reports expected labels", {
    crash <- list(package = "pkg1", errors = "crash", warnings = character(), notes = character(), crashed = TRUE)
    fail <- list(package = "pkg2", errors = c("e1"), warnings = character(), notes = character(), crashed = FALSE)
    warn <- list(package = "pkg3", errors = character(), warnings = c("w1"), notes = character(), crashed = FALSE)
    note <- list(package = "pkg4", errors = character(), warnings = character(), notes = c("n1"), crashed = FALSE)
    pass <- list(package = "pkg5", errors = character(), warnings = character(), notes = character(), crashed = FALSE)

    expect_equal(revdep_status(crash), "CRASH")
    expect_equal(revdep_status(fail), "FAIL")
    expect_equal(revdep_status(warn), "WARN")
    expect_equal(revdep_status(note), "NOTE")
    expect_equal(revdep_status(pass), "PASS")
})

test_that("revdep_status_table returns a data frame", {
    results <- list(
        list(package = "pkgA", errors = character(), warnings = character(), notes = character(), crashed = FALSE),
        list(package = "pkgB", errors = "boom", warnings = character(), notes = character(), crashed = FALSE)
    )

    tbl <- revdep_status_table(results)
    expect_s3_class(tbl, "data.frame")
    expect_equal(nrow(tbl), 2)
    expect_equal(tbl$Status, c("PASS", "FAIL"))
})
