#' Run a simple reverse dependency check
#'
#' Installs the local package (from the current directory) to ensure the latest
#' version is used, discovers CRAN reverse dependencies for a target package,
#' optionally filters to a subset, downloads source tarballs, and runs
#' `rcmdcheck()` on one selected package. Returns raw results and a compact
#' summary; results are saved to `check_dir`.
#'
#' @param target_package Character; package whose reverse dependencies to query
#'   (e.g., "did"). If the current directory is that package, it is (re)installed
#'   locally first to avoid using an outdated version.
#' @param reverse_deps Optional character vector of CRAN package names to
#'   check. When `NULL`, reverse dependencies are discovered automatically via CRAN metadata.
#' @param check_dir Directory to store downloaded tarballs and saved results.
#' @param check_args Arguments forwarded to `R CMD check`.
#' @param build_args Arguments forwarded to `R CMD build`.
#' @param quiet Logical; passed to `rcmdcheck()`.
#'
#' @return A list with elements `results` (raw `rcmdcheck` output), `summary`
#'   (data frame), and `check_dir`.
#' @export
simple_revdep_check <- function(target_package,
                                reverse_deps = NULL,
                                check_dir = ".simple_revdep",
                                check_args = c("--no-manual", "--as-cran"),
                                build_args = "--no-build-vignettes",
                                quiet = TRUE) {
    if (missing(target_package) || is.null(target_package) || !nzchar(target_package)) {
        stop("Please provide `target_package` (e.g., \"did\").")
    }

    # Install the local package only if it matches target_package
    install_current_package_if_target(target_package)

    # Determine reverse dependencies (from CRAN metadata)
    if (is.null(reverse_deps)) {
        reverse_deps <- get_reverse_dependencies(target_package = target_package)
    }
    if (length(reverse_deps) == 0) {
        stop("No reverse dependencies to check for target package: ", target_package)
    }

    dir.create(check_dir, showWarnings = FALSE, recursive = TRUE)
    utils::download.packages(reverse_deps, destdir = check_dir, type = "source")

    files <- list.files(check_dir, pattern = "\\.tar\\.gz$", full.names = TRUE)
    if (length(files) == 0) {
        stop("No downloaded packages found in ", check_dir)
    }

    # For simplicity, check the first package deterministically
    result <- check_tarball(files[[1L]], check_args = check_args, build_args = build_args, quiet = quiet)
    summary <- revdep_status_table(list(result))

    saveRDS(list(result), file.path(check_dir, "check_results.rds"))

    list(results = result, summary = summary, check_dir = check_dir)
}
get_reverse_dependencies <- function(target_package = NULL) {
    if (is.null(target_package)) {
        desc_path <- file.path(getwd(), "DESCRIPTION")
        if (!file.exists(desc_path)) {
            stop("No DESCRIPTION found in the current directory")
        }
        dcf <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
        if (is.null(dcf)) {
            stop("Failed to read DESCRIPTION file")
        }
        pkg <- dcf[1, "Package"]
        if (is.na(pkg) || !nzchar(pkg)) {
            stop("DESCRIPTION is missing a Package field")
        }
    } else {
        pkg <- target_package
    }

    # Query CRAN metadata for reverse dependencies
    rev <- tools::package_dependencies(packages = pkg, reverse = TRUE, repositories = getOption("repos"))
    unique(unname(rev[[pkg]] %||% character()))
}

#' Summarize reverse dependency check results
#'
#' @param results List of objects returned by `rcmdcheck()` (or crash stubs).
#'
#' @return Data frame with columns `Package`, `Errors`, `Warnings`, `Notes`,
#'   and `Status`.
#' @export
revdep_status_table <- function(results) {
    if (length(results) == 0) {
        return(data.frame())
    }

    data.frame(
        Package = vapply(results, function(r) r$package, character(1L)),
        Errors = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$errors), integer(1L)),
        Warnings = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$warnings), integer(1L)),
        Notes = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$notes), integer(1L)),
        Status = vapply(results, revdep_status, character(1L)),
        stringsAsFactors = FALSE
    )
}

install_current_package_if_target <- function(target_package) {
    desc_path <- file.path(getwd(), "DESCRIPTION")
    if (!file.exists(desc_path)) {
        return(invisible(FALSE))
    }

    dcf <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
    if (is.null(dcf)) {
        return(invisible(FALSE))
    }
    pkg <- dcf[1, "Package"]
    ver <- dcf[1, "Version"]

    if (is.na(pkg) || !nzchar(pkg) || !identical(pkg, target_package)) {
        return(invisible(FALSE))
    }

    reinstall <- TRUE
    if (requireNamespace(pkg, quietly = TRUE)) {
        installed_ver <- tryCatch(utils::packageVersion(pkg), error = function(e) NA)
        reinstall <- is.na(installed_ver) || as.character(installed_ver) != ver
    }

    if (reinstall) {
        if (requireNamespace("devtools", quietly = TRUE)) {
            devtools::install(upgrade = "never")
        } else {
            system2(
                command = file.path(R.home("bin"), "R"),
                args = c("CMD", "INSTALL", "."),
                stdout = TRUE, stderr = TRUE
            )
        }
    }

    invisible(TRUE)
}

upgrade_reverse_deps <- function(pkgs) {
    if (length(pkgs) == 0) {
        return(invisible())
    }
    if (requireNamespace("pak", quietly = TRUE)) {
        pak::pkg_install(pkgs, upgrade = TRUE)
    } else {
        utils::install.packages(pkgs, dependencies = TRUE)
    }
}

check_tarball <- function(path, check_args, build_args, quiet) {
    pkg_name <- sub("_.*", "", basename(path))

    res <- tryCatch(
        rcmdcheck::rcmdcheck(
            path,
            args = check_args,
            build_args = build_args,
            quiet = quiet
        ),
        error = function(e) {
            list(
                package = pkg_name,
                errors = paste("Check crashed:", e$message),
                warnings = character(0),
                notes = character(0),
                crashed = TRUE
            )
        }
    )

    if (!"crashed" %in% names(res)) {
        res$crashed <- FALSE
    }
    res$package <- pkg_name
    res
}

parallel_map <- function(x, fun, cores) {
    # Not used in the simplified single-package flow, kept for potential future use.
    lapply(x, fun)
}

revdep_status <- function(result) {
    if (isTRUE(result$crashed)) {
        return("CRASH")
    }
    if (length(result$errors) > 0) {
        return("FAIL")
    }
    if (length(result$warnings) > 0) {
        return("WARN")
    }
    if (length(result$notes) > 0) {
        return("NOTE")
    }
    "PASS"
}

`%||%` <- function(a, b) {
    if (is.null(a)) b else a
}
