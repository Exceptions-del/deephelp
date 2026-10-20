# Configuration ---------------------------------------------------------------

#' Configure the DeepSeek backend
#'
#' @param api_key DeepSeek API key. Falls back to `getOption("deephelp.api_key")`
#'   and then the `DEEPSEEK_API_KEY` environment variable.
#' @param model Model name. Defaults to `"deepseek-flash"` (fast, cheap,
#'   non-reasoning). Use `"deepseek-v4-pro"` for higher quality at higher cost.
#' @param base_url API base URL. Defaults to `"https://api.deepseek.com"`.
#' @param lang Target language. Defaults to Simplified Chinese.
#' @param cache Cache directory. `NULL` uses the default location; `""` disables
#'   caching; otherwise a directory path.
#' @param temperature Optional sampling temperature passed to the API.
#' @param max_tokens Optional maximum number of output tokens.
#' @param timeout HTTP timeout in seconds.
#' @param cjk_spacing Logical. Insert consistent single spaces between Chinese
#'   and Latin letters/digits (and around code) in the translated output.
#'   Defaults to `TRUE`.
#' @param glossary Named character vector mapping English statistical terms to
#'   Chinese translations. Merged over the built-in glossary; use
#'   `character(0)` to disable the glossary entirely.
#' @export
deephelp_use <- function(api_key = NULL, model = NULL, base_url = NULL,
                         lang = NULL, cache = NULL, temperature = NULL,
                         max_tokens = NULL, timeout = NULL,
                         cjk_spacing = NULL, glossary = NULL) {
  cfg <- .dh$config
  if (!is.null(api_key))     cfg$api_key     <- api_key
  if (!is.null(model))       cfg$model       <- model
  if (!is.null(base_url))    cfg$base_url    <- base_url
  if (!is.null(lang))        cfg$lang        <- lang
  if (!is.null(cache))       cfg$cache       <- cache
  if (!is.null(temperature)) cfg$temperature <- temperature
  if (!is.null(max_tokens))  cfg$max_tokens  <- max_tokens
  if (!is.null(timeout))     cfg$timeout     <- timeout
  if (!is.null(cjk_spacing)) cfg$cjk_spacing <- cjk_spacing
  if (!is.null(glossary))    cfg$glossary    <- merge_glossary(glossary)
  .dh$config <- cfg
  deephelp_status()
  invisible(cfg)
}

# Merge user glossary over the built-in default. `character(0)` clears it.
merge_glossary <- function(user) {
  if (length(user) == 0L) {
    return(character(0))
  }
  if (is.null(names(user)) || any(!nzchar(names(user)))) {
    stop("`glossary` must be a named character vector, e.g. c(regression = \"\u56de\u5f52\").",
         call. = FALSE)
  }
  out <- .dh$default_glossary
  out[names(user)] <- user
  out
}

#' Print the current configuration
#'
#' @examples
#' deephelp_status()
#'
#' @export
deephelp_status <- function() {
  cfg <- .dh$config
  key <- resolve_api_key()
  cache_str <- if (is.null(cfg$cache)) {
    tools::R_user_dir("deephelp", "cache")
  } else if (!nzchar(cfg$cache)) {
    "(disabled)"
  } else {
    cfg$cache
  }
  key_str <- if (nzchar(key)) {
    paste0(substr(key, 1L, 4L), "****", substr(key, nchar(key) - 3L, nchar(key)))
  } else {
    "<not set>"
  }
  gloss <- if (is.null(cfg$glossary)) .dh$default_glossary else cfg$glossary
  message("deephelp configuration:")
  message("  Model      : ", cfg$model)
  message("  Base URL   : ", cfg$base_url)
  message("  API key    : ", key_str)
  message("  Language   : ", cfg$lang)
  message("  Cache      : ", cache_str)
  message("  CJK spacing: ", if (isTRUE(cfg$cjk_spacing)) "on (pangu)" else "off")
  message("  Glossary   : ", length(gloss), " term(s)")
  message("  Reasoning  : disabled (thinking mode is always off)")
  invisible(cfg)
}

#' Enable automatic translation of `?` and `help()`
#' @export
deephelp_on <- function() {
  options(deephelp.enabled = TRUE)
  tryCatch(attach_shims(), error = function(e) NULL)
  message("deephelp is ON: `?` and help() now translate.")
  invisible(TRUE)
}

#' Disable automatic translation of `?` and `help()`
#' @export
deephelp_off <- function() {
  options(deephelp.enabled = FALSE)
  message("deephelp is OFF: `?` and help() use the original help.")
  invisible(FALSE)
}

#' Clear the translation cache
#' @param cache Cache directory to clear. Defaults to the current cache location.
#' @export
deephelp_clear_cache <- function(cache = NULL) {
  root <- cache
  if (is.null(root) || !nzchar(root)) {
    root <- tools::R_user_dir("deephelp", "cache")
  }
  if (dir.exists(root)) {
    n <- length(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
    unlink(root, recursive = TRUE, force = TRUE)
    message("Cleared ", n, " cached translation(s) from ", root)
  } else {
    message("No cache directory at ", root)
  }
  invisible(NULL)
}

resolve_api_key <- function() {
  k <- .dh$config$api_key
  if (is.null(k) || !nzchar(k)) k <- getOption("deephelp.api_key", NULL)
  if (is.null(k) || !nzchar(k)) k <- Sys.getenv("DEEPSEEK_API_KEY", unset = NA)
  if (is.na(k)) k <- ""
  k
}
