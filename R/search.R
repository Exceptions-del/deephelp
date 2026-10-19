# Fuzzy help search translation (`??`, help.search) ---------------------------

#' Translate fuzzy help-search results (`??`, `help.search`)
#'
#' @param pattern Keyword pattern to search for.
#' @param package Optional package name to restrict the search.
#' @param ... Passed to [utils::help.search()].
#' @export
deephelp_search <- function(pattern, package = NULL, ...) {
  cfg <- .dh$config
  hs <- utils::help.search(pattern, package = package, ...)
  if (is.data.frame(hs$matches) && nrow(hs$matches) > 0L) {
    message("deephelp: translating ", nrow(hs$matches),
            " search-result title(s) ...")
    hs$matches$Title <- translate_titles(hs$matches$Title, cfg)
  }
  hs
}

translate_titles <- function(titles, cfg) {
  if (length(titles) == 0L) {
    return(titles)
  }
  root <- cache_root(cfg)
  hash <- config_hash(cfg)
  out <- character(length(titles))
  todo <- logical(length(titles))

  if (is.null(root)) {
    todo[] <- TRUE
  } else {
    cache_dir <- file.path(root, "_search")
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    for (i in seq_along(titles)) {
      f <- file.path(cache_dir,
                     paste0(md5_char(c(titles[i], cfg$lang, hash)), ".rds"))
      val <- if (file.exists(f)) {
        tryCatch(readRDS(f), error = function(e) NULL)
      } else {
        NULL
      }
      if (is.character(val) && length(val) == 1L && nzchar(val)) {
        out[i] <- val
      } else {
        todo[i] <- TRUE
      }
    }
  }

  if (any(todo)) {
    tr <- translate_batch(titles[todo], cfg$lang, cfg)
    if (isTRUE(cfg$cjk_spacing)) {
      tr <- vapply(tr, cjk_spacing_text, character(1))
    }
    out[todo] <- tr
    if (!is.null(root)) {
      cache_dir <- file.path(root, "_search")
      for (i in which(todo)) {
        f <- file.path(cache_dir,
                       paste0(md5_char(c(titles[i], cfg$lang, hash)), ".rds"))
        try(saveRDS(out[i], f), silent = TRUE)
      }
    }
  }
  out
}
