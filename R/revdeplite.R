# =============================================================================
# Title: revdeplite — Lightweight Reverse Dependency Check
# Description: Core implementation: revdeplite(), check_source(), and helpers
#   for discovering, cloning, and summarising reverse dependency checks.
# Author: Brant Callaway
# Last update: 2026-05-25
# Date created: 2026-05-25
# =============================================================================

# --- Helpers -----------------------------------------------------------------

`%||%` <- function(a, b) {
    if (is.null(a)) b else a
}

revdep_status <- function(result) {
    if (isTRUE(result$crashed)) return("CRASH")
    if (length(result$errors)   > 0) return("FAIL")
    if (length(result$warnings) > 0) return("WARN")
    if (length(result$notes)    > 0) return("NOTE")
    "PASS"
}

# Read the Package field from a DESCRIPTION file in a source directory,
# falling back to tarball-filename parsing for .tar.gz paths.
get_pkg_name <- function(path) {
    if (dir.exists(path)) {
        desc <- file.path(path, "DESCRIPTION")
        if (file.exists(desc)) {
            tryCatch(read.dcf(desc)[1L, "Package"], error = function(e) basename(path))
        } else {
            basename(path)
        }
    } else {
        sub("_.*", "", basename(path))
    }
}

# --- Core check --------------------------------------------------------------

# Runs rcmdcheck on a single source (tarball path or source directory).
# Returns the rcmdcheck result object augmented with $package, $source,
# and $crashed fields.
check_source <- function(path, source_type, check_args, build_args, quiet) {
    pkg_name <- get_pkg_name(path)

    res <- tryCatch(
        rcmdcheck::rcmdcheck(
            path,
            args      = check_args,
            build_args = build_args,
            quiet     = quiet,
            env       = c("_R_CHECK_FORCE_SUGGESTS_" = "false",
                          "_R_CHECK_SYSTEM_CLOCK_"   = "false")
        ),
        error = function(e) {
            list(
                package  = pkg_name,
                errors   = paste("Check crashed:", e$message),
                warnings = character(0),
                notes    = character(0),
                crashed  = TRUE
            )
        }
    )

    res$crashed <- isTRUE(res$crashed)
    res$package <- pkg_name
    res$source  <- source_type
    res
}

# Clone (or update) a GitHub repo for checking.
# repo: "user/package" format.
# Returns the path to the cloned directory, or "" on failure.
clone_github_package <- function(repo, dest_dir) {
    pkg_name   <- sub(".*/", "", repo)
    clone_path <- file.path(dest_dir, pkg_name)

    if (dir.exists(clone_path)) {
        message("  Updating existing clone of ", repo, "...")
        ret <- system2("git", c("-C", clone_path, "pull", "--quiet"),
                       stdout = FALSE, stderr = FALSE)
    } else {
        message("  Cloning ", repo, "...")
        url <- paste0("https://github.com/", repo, ".git")
        ret <- system2("git",
                       c("clone", "--depth=1", "--quiet", url, clone_path),
                       stdout = FALSE, stderr = FALSE)
    }

    if (ret != 0 || !dir.exists(clone_path)) {
        warning("Failed to clone ", repo, " (exit code ", ret, ")")
        return("")
    }
    clone_path
}

# --- Printing ----------------------------------------------------------------

print_detailed_results <- function(results) {
    message("\n", strrep("=", 70))
    message("=== Detailed Results by Package ===")
    message(strrep("=", 70))

    # Iterate by index (not name) to handle duplicate package names (CRAN + GitHub).
    # Show CRAN entries first, then GitHub.
    sources   <- vapply(results, function(r) r$source %||% "cran", character(1L))
    idx_order <- c(which(sources == "cran"), which(sources == "github"))

    for (i in idx_order) {
        result       <- results[[i]]
        pkg_name     <- result$package
        source_label <- paste0(" [", toupper(result$source %||% "cran"), "]")

        message("\n", strrep("-", 70))
        message("Package: ", pkg_name, source_label)
        message(strrep("-", 70))

        if (isTRUE(result$crashed)) {
            message("  ❌ CHECK CRASHED")
            message("  Error: ", result$errors)
        } else {
            status <- revdep_status(result)
            status_icon <- switch(status,
                CRASH = "❌", FAIL = "❌", WARN = "⚠️ ",
                NOTE  = "📝", PASS = "✅", "  "
            )
            message("  Status: ", status_icon, " ", status)
            message("  Errors: ",   length(result$errors))
            message("  Warnings: ", length(result$warnings))
            message("  Notes: ",    length(result$notes))

            if (length(result$errors) > 0) {
                message("\n  ERRORS:")
                for (err in result$errors) message("    • ", err)
            }
            if (length(result$warnings) > 0) {
                message("\n  WARNINGS:")
                for (warn in result$warnings) message("    • ", warn)
            }
            if (length(result$notes) > 0) {
                message("\n  NOTES:")
                for (note in result$notes) message("    • ", note)
            }
        }
    }

    message("\n", strrep("=", 70))
}

# --- Exported functions ------------------------------------------------------

#' Run a lightweight reverse dependency check
#'
#' Installs the local package (from the current directory) to ensure the
#' latest version is used, discovers CRAN reverse dependencies, optionally
#' adds GitHub packages, downloads/clones sources, runs `rcmdcheck()` on
#' each, and returns a compact summary. Results are saved to `check_dir`.
#'
#' @param target_package Optional character; package whose reverse
#'   dependencies to query (e.g., `"BMisc"`). Defaults to the package in
#'   the current directory. If the current directory is that package, it is
#'   (re)installed locally first so the latest version is used.
#' @param reverse_deps Optional character vector of CRAN package names to
#'   check. When `NULL`, reverse dependencies are discovered automatically
#'   via CRAN metadata.
#' @param github_deps Optional character vector of GitHub repositories in
#'   `"user/repo"` format (e.g., `c("bcallaway11/did", "pedrohcgs/DRDID")`).
#'   Each repo is cloned (or updated) with `git clone --depth=1` and checked
#'   alongside the CRAN packages. Requires `git` to be available on `PATH`.
#'   Results are labelled `"github"` in the summary `Source` column.
#' @param check_dir Directory to store downloaded tarballs, cloned repos,
#'   and saved results.
#' @param num_cores Number of cores for parallel checking. Defaults to 1
#'   (sequential). Parallel mode works on Linux and Windows.
#' @param check_args Arguments forwarded to `R CMD check`. Defaults to
#'   `"--no-manual"`. Note: `--as-cran` is intentionally omitted to avoid
#'   false-positive NOTEs (version mismatch, build timestamp) that are
#'   irrelevant for reverse dependency checking.
#' @param build_args Arguments forwarded to `R CMD build`.
#' @param quiet Logical; passed to `rcmdcheck()`.
#'
#' @return A list with elements `results` (named list of raw `rcmdcheck`
#'   output), `summary` (data frame with columns `Package`, `Source`,
#'   `Errors`, `Warnings`, `Notes`, `Status`), and `check_dir`. A markdown
#'   report is written to `check_dir/revdep-results.md`.
#' @export
revdeplite <- function(target_package = NULL,
                                reverse_deps   = NULL,
                                github_deps    = NULL,
                                check_dir      = ".revdeplite",
                                num_cores      = 1L,
                                check_args     = "--no-manual",
                                build_args     = "--no-build-vignettes",
                                quiet          = TRUE) {
    # --- Resolve target package ----------------------------------------------
    if (is.null(target_package)) {
        desc_path <- file.path(getwd(), "DESCRIPTION")
        if (!file.exists(desc_path)) stop("No DESCRIPTION found in the current directory")
        dcf <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
        if (is.null(dcf)) stop("Failed to read DESCRIPTION file")
        target_package <- dcf[1L, "Package"]
        if (is.na(target_package) || !nzchar(target_package))
            stop("DESCRIPTION is missing a Package field")
    }

    message("\n=== revdeplite: Reverse Dependency Check ===")
    message("Target package: ", target_package)

    # --- Install local package -----------------------------------------------
    message("\nChecking local package installation...")
    install_current_package_if_target(target_package)

    # --- CRAN reverse dependencies -------------------------------------------
    message("\nDiscovering CRAN reverse dependencies...")
    if (is.null(reverse_deps)) {
        reverse_deps <- get_reverse_dependencies(target_package = target_package)
    }

    dir.create(check_dir, showWarnings = FALSE, recursive = TRUE)

    # Remove stale tarballs from previous runs so re-runs don't check both old
    # and new versions of the same package. GitHub clones are kept and updated
    # via git pull instead of re-cloning from scratch.
    old_tarballs <- list.files(check_dir, pattern = "\\.tar\\.gz$", full.names = TRUE)
    if (length(old_tarballs) > 0) {
        message("Removing ", length(old_tarballs), " stale tarball(s) from previous run...")
        file.remove(old_tarballs)
    }

    cran_paths <- character(0)
    if (length(reverse_deps) > 0) {
        message("Found ", length(reverse_deps), " CRAN reverse dependencies: ",
                paste(reverse_deps, collapse = ", "))
        message("\nInstalling/upgrading CRAN reverse dependencies...")
        upgrade_reverse_deps(reverse_deps)
        message("\nDownloading CRAN source packages...")
        utils::download.packages(reverse_deps, destdir = check_dir, type = "source")
        cran_paths <- list.files(check_dir, pattern = "\\.tar\\.gz$", full.names = TRUE)
    } else {
        message("No CRAN reverse dependencies found.")
    }

    # --- GitHub packages -----------------------------------------------------
    github_paths <- character(0)
    if (!is.null(github_deps) && length(github_deps) > 0) {
        message("\nCloning GitHub packages...")
        github_dir <- file.path(check_dir, "github")
        dir.create(github_dir, showWarnings = FALSE, recursive = TRUE)
        cloned <- vapply(github_deps, clone_github_package,
                         dest_dir = github_dir, FUN.VALUE = character(1L))
        github_paths <- cloned[nzchar(cloned)]
    }

    # --- Merge and validate --------------------------------------------------
    # Each source carries its type so the summary table can label it.
    all_sources <- c(
        setNames(as.list(cran_paths),    rep("cran",   length(cran_paths))),
        setNames(as.list(github_paths),  rep("github", length(github_paths)))
    )
    source_types <- names(all_sources)
    sources      <- unlist(all_sources, use.names = FALSE)

    if (length(sources) == 0) {
        stop("No packages to check (no CRAN downloads and no successful GitHub clones).")
    }

    # --- Run checks ----------------------------------------------------------
    num_cores <- max(1L, as.integer(num_cores))
    n <- length(sources)

    run_one <- function(i) {
        check_source(sources[[i]], source_types[[i]],
                     check_args = check_args,
                     build_args = build_args,
                     quiet      = quiet)
    }

    if (num_cores == 1L) {
        message("\n=== Running R CMD check on ", n, " packages (sequential) ===")
        results <- lapply(seq_len(n), function(i) {
            pkg_name <- get_pkg_name(sources[[i]])
            message("\n[", i, "/", n, "] Checking ", pkg_name,
                    " (", source_types[[i]], ")...")
            t0  <- proc.time()
            res <- run_one(i)
            elapsed <- round((proc.time() - t0)[["elapsed"]])
            message("  -> ", revdep_status(res), " [", elapsed, "s]")
            res
        })
    } else {
        message("\n=== Running R CMD check on ", n, " packages (parallel, ",
                num_cores, " cores) ===")
        cl <- parallel::makeCluster(num_cores)
        on.exit(parallel::stopCluster(cl), add = TRUE)
        parallel::clusterExport(
            cl,
            c("check_source", "get_pkg_name", "sources", "source_types",
              "check_args", "build_args", "quiet"),
            envir = environment()
        )
        results <- parallel::parLapply(cl, seq_len(n), run_one)
    }

    names(results) <- vapply(results, function(r) r$package, character(1L))

    # --- Report --------------------------------------------------------------
    summary_df <- revdep_status_table(results)
    print_revdep_summary(summary_df)
    print_detailed_results(results)

    saveRDS(results, file.path(check_dir, "check_results.rds"))
    message("\nResults saved to: ", file.path(check_dir, "check_results.rds"))
    write_revdep_report(results, summary_df,
                        check_dir      = check_dir,
                        target_package = target_package)

    list(results = results, summary = summary_df, check_dir = check_dir)
}


#' Print saved reverse dependency check results
#'
#' Load and display previously saved results from an RDS file.
#'
#' @param check_dir Directory containing `check_results.rds`, or a direct
#'   path to an `.rds` file. Defaults to `".revdeplite"`.
#'
#' @return Invisibly returns the list of results.
#' @export
print_revdep_results <- function(check_dir = ".revdeplite") {
    rds_path <- if (grepl("\\.rds$", check_dir, ignore.case = TRUE)) {
        check_dir
    } else {
        file.path(check_dir, "check_results.rds")
    }
    if (!file.exists(rds_path)) stop("Results file not found: ", rds_path)

    message("Loading results from: ", rds_path)
    results <- readRDS(rds_path)

    summary_df <- revdep_status_table(results)
    print_revdep_summary(summary_df)
    print_detailed_results(results)

    invisible(results)
}


#' Summarize reverse dependency check results
#'
#' @param results Named list of objects returned by `rcmdcheck()` (or crash
#'   stubs).
#'
#' @return Data frame with columns `Package`, `Source`, `Errors`, `Warnings`,
#'   `Notes`, and `Status`.
#' @export
revdep_status_table <- function(results) {
    if (length(results) == 0) return(data.frame())

    data.frame(
        Package  = vapply(results, function(r) r$package, character(1L)),
        Source   = vapply(results, function(r) r$source %||% "cran", character(1L)),
        Errors   = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$errors),   integer(1L)),
        Warnings = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$warnings), integer(1L)),
        Notes    = vapply(results, function(r) if (isTRUE(r$crashed)) NA_integer_ else length(r$notes),    integer(1L)),
        Status   = vapply(results, revdep_status, character(1L)),
        stringsAsFactors = FALSE
    )
}


#' Print a split summary of reverse dependency check results
#'
#' Prints one table for CRAN packages and one for GitHub packages, depending
#' on which source types are present. Accepts either the named results list or
#' the summary data frame returned by [revdep_status_table()].
#'
#' @param results Named list of `rcmdcheck` results, or a data frame from
#'   [revdep_status_table()].
#' @return Invisibly returns the summary data frame.
#' @export
print_revdep_summary <- function(results) {
    df   <- if (is.data.frame(results)) results else revdep_status_table(results)
    cols <- c("Package", "Errors", "Warnings", "Notes", "Status")

    cran_df   <- df[df$Source == "cran",   cols, drop = FALSE]
    github_df <- df[df$Source == "github", cols, drop = FALSE]

    if (nrow(cran_df) > 0) {
        message("\n=== CRAN Packages ===")
        print(cran_df, row.names = FALSE)
    }
    if (nrow(github_df) > 0) {
        message("\n=== GitHub Packages ===")
        print(github_df, row.names = FALSE)
    }

    invisible(df)
}


#' Write a markdown report of reverse dependency check results
#'
#' Saves a human-readable `revdeplite-results.md` to `check_dir` with summary
#' tables (CRAN and GitHub separately) and per-package details including all
#' errors, warnings, and notes.
#'
#' @param results Named list of `rcmdcheck` results (or crash stubs).
#' @param summary_df Data frame from [revdep_status_table()]. If `NULL`,
#'   computed from `results`.
#' @param check_dir Directory to write `revdeplite-results.md`. Defaults to
#'   `".revdeplite"`.
#' @param target_package Optional character; package name for the report header.
#' @return Invisibly returns the path to the written file.
#' @export
write_revdep_report <- function(results, summary_df = NULL,
                                check_dir      = ".revdeplite",
                                target_package = NULL) {
    if (is.null(summary_df)) summary_df <- revdep_status_table(results)

    pkg_label <- target_package %||% "unknown"
    lines <- c(
        paste0("# Reverse Dependency Check: ", pkg_label),
        "",
        paste0("**Date:** ", Sys.Date()),
        ""
    )

    # --- Summary tables -------------------------------------------------------
    cols      <- c("Package", "Errors", "Warnings", "Notes", "Status")
    cran_df   <- summary_df[summary_df$Source == "cran",   cols, drop = FALSE]
    github_df <- summary_df[summary_df$Source == "github", cols, drop = FALSE]

    # Pad each column to max width for alignment in the raw markdown file.
    md_table <- function(df) {
        widths <- mapply(
            function(nm, vals) max(nchar(nm), max(nchar(as.character(vals)), 0L)),
            cols, as.list(df)
        )
        pad    <- function(x, w) formatC(as.character(x), width = -w, flag = "-")
        header <- paste("|", paste(mapply(pad, cols,          widths), collapse = " | "), "|")
        sep    <- paste("|", paste(mapply(function(w) strrep("-", w), widths), collapse = " | "), "|")
        rows   <- apply(df, 1, function(r) {
            paste("|", paste(mapply(pad, r, widths), collapse = " | "), "|")
        })
        c(header, sep, rows)
    }

    if (nrow(cran_df) > 0) {
        lines <- c(lines, "## CRAN Packages", "", md_table(cran_df), "")
    }
    if (nrow(github_df) > 0) {
        lines <- c(lines, "## GitHub Packages", "", md_table(github_df), "")
    }

    # --- Per-package details: CRAN first, then GitHub -------------------------
    # Iterate by index (not name) — duplicate package names (same pkg in both
    # CRAN and GitHub) would cause results[[name]] to always return the first match.
    lines   <- c(lines, "## Details", "")
    sources <- vapply(results, function(r) r$source %||% "cran", character(1L))
    for (i in c(which(sources == "cran"), which(sources == "github"))) {
        result       <- results[[i]]
        source_label <- toupper(result$source %||% "cran")
        status       <- revdep_status(result)

        lines <- c(lines,
            paste0("### ", result$package, " [", source_label, "] — ", status),
            ""
        )

        if (isTRUE(result$crashed)) {
            lines <- c(lines, "**CHECK CRASHED**", "",
                       paste0("- ", result$errors), "")
        } else {
            if (length(result$errors) > 0) {
                lines <- c(lines, "#### Errors", "",
                           paste0("- ", result$errors), "")
            }
            if (length(result$warnings) > 0) {
                lines <- c(lines, "#### Warnings", "",
                           paste0("- ", result$warnings), "")
            }
            if (length(result$notes) > 0) {
                lines <- c(lines, "#### Notes", "",
                           paste0("- ", result$notes), "")
            }
            if (length(result$errors) == 0 &&
                length(result$warnings) == 0 &&
                length(result$notes) == 0) {
                lines <- c(lines, "No issues.", "")
            }
        }
        lines <- c(lines, "---", "")
    }

    dir.create(check_dir, showWarnings = FALSE, recursive = TRUE)
    out_path <- file.path(check_dir, "revdeplite-results.md")
    writeLines(lines, out_path)
    message("Report written to: ", out_path)
    invisible(out_path)
}


# --- Internal helpers --------------------------------------------------------

get_reverse_dependencies <- function(target_package = NULL) {
    if (is.null(target_package)) {
        desc_path <- file.path(getwd(), "DESCRIPTION")
        if (!file.exists(desc_path)) stop("No DESCRIPTION found in the current directory")
        dcf <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
        if (is.null(dcf)) stop("Failed to read DESCRIPTION file")
        pkg <- dcf[1L, "Package"]
        if (is.na(pkg) || !nzchar(pkg)) stop("DESCRIPTION is missing a Package field")
    } else {
        pkg <- target_package
    }
    rev <- tools::package_dependencies(
        packages = pkg,
        which    = c("Depends", "Imports", "Suggests", "LinkingTo"),
        reverse  = TRUE
    )
    unique(unname(rev[[pkg]] %||% character()))
}

install_current_package_if_target <- function(target_package) {
    desc_path <- file.path(getwd(), "DESCRIPTION")
    if (!file.exists(desc_path)) return(invisible(FALSE))

    dcf <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
    if (is.null(dcf)) return(invisible(FALSE))
    pkg <- dcf[1L, "Package"]
    ver <- dcf[1L, "Version"]

    if (is.na(pkg) || !nzchar(pkg) || !identical(pkg, target_package))
        return(invisible(FALSE))

    reinstall <- TRUE
    if (requireNamespace(pkg, quietly = TRUE)) {
        installed_ver <- tryCatch(utils::packageVersion(pkg), error = function(e) NA)
        reinstall <- is.na(installed_ver) || as.character(installed_ver) != ver
    }

    if (reinstall) {
        if (requireNamespace("devtools", quietly = TRUE)) {
            devtools::install(upgrade = "never")
        } else {
            system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", "."),
                    stdout = TRUE, stderr = TRUE)
        }
    }
    invisible(TRUE)
}

upgrade_reverse_deps <- function(pkgs) {
    if (length(pkgs) == 0) return(invisible())
    if (requireNamespace("pak", quietly = TRUE)) {
        pak::pkg_install(pkgs, upgrade = TRUE)
    } else {
        utils::install.packages(pkgs, dependencies = TRUE)
    }
}
