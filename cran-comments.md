## Test environments

* local Windows 10 (x86_64-w64-mingw32), R 4.5.3

## R CMD check results

0 errors | 0 warnings | 0 notes

## Downstream dependencies

None. This is a new submission.

## Notes to CRAN maintainers

* This is the first submission of the package.

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
