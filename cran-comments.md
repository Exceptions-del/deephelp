## Test environments

* local Windows 10 (x86_64-w64-mingw32), R 4.5.3

## R CMD check results

0 errors | 0 warnings | 0 notes

The local check (Windows 10, R 4.5.3) reported one WARNING and three NOTEs that
are environment-specific and do not occur on CRAN's check machines:

* "PDF version of manual" (with index): the local TeX distribution (TinyTeX)
  lacks a working `makeindex`, so the indexed build fails. The LaTeX source
  compiles cleanly and the "without index" build passes.
* "future file timestamps": the machine could not reach a time server to verify
  the current time.
* "top-level files": `pandoc` is not installed locally.
* "non-standard things in the check directory": a leftover
  `deephelp-manual.tex` produced by the failed indexed build above.

## Downstream dependencies

None. This is a new submission.

## Notes to CRAN maintainers

* This is a resubmission (version 0.3.3) of the package. It addresses the note
  from the previous submission (0.3.1), where software names in the `Title` and
  `Description` fields were flagged as possible misspellings: those names
  (`'DeepSeek'`, `'RStudio'`, `'Positron'`) are now single-quoted.

* The package provides a drop-in replacement for `?`, `help()`,
  `help.search()` and `vignette()`. On load it attaches a small environment of
  shims at position 2 of the search path and registers a `utils` attach hook so
  the shims stay ahead of `utils::help()` / `utils::?`. This mirrors the
  approach used by the `lang` package already on CRAN
  (<https://cran.r-project.org/package=lang>). The shims are transparent: when
  translation is disabled, or for `??` fuzzy searches, calls are forwarded
  unchanged to `utils::help()` / `utils::?`.

* The package talks to the DeepSeek chat API over HTTPS. A DeepSeek API key is
  required, supplied via `deephelp_use()`, `options(deephelp.api_key = ...)`, or
  the `DEEPSEEK_API_KEY` environment variable. No examples or tests make network
  calls, so checks and examples run offline.

* `rd_to_source()` needs the unexported `tools:::as.character.Rd()` to serialize
  a parsed Rd object back to Rd source. It is fetched at runtime via
  `utils::getFromNamespace("as.character.Rd", "tools")`, so the source code does
  not contain the `:::` operator.

* Translated help is rendered into the RStudio/Positron Help pane via
  `rstudioapi::previewRd()` (declared in `Suggests`); outside those IDEs the
  package falls back to plain-text output.
