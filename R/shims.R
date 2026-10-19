# Help system shims -----------------------------------------------------------

attach_shims <- function() {
  if ("deephelp_shims" %in% search()) {
    base::detach("deephelp_shims", character.only = TRUE)
  }
  e <- new.env(parent = globalenv())
  e$help        <- shim_help
  e$`?`         <- shim_question
  e$help.search <- shim_help_search
  e$vignette    <- shim_vignette
  # Attach explicitly at position 2 (immediately after .GlobalEnv) so the shims
  # shadow utils::help() / utils::? instead of being shadowed by them.
  base::attach(what = e, name = "deephelp_shims", pos = 2L, warn.conflicts = FALSE)
  invisible()
}

deephelp_enabled <- function() {
  isTRUE(getOption("deephelp.enabled", TRUE))
}

# Drop-in replacement for utils::help()
shim_help <- function(topic, package = NULL, ...) {
  cl <- match.call()
  if (!deephelp_enabled() || is.null(cl[["topic"]])) {
    cl[[1L]] <- quote(utils::help)
    return(eval(cl, parent.frame()))
  }
  topic_expr <- cl[["topic"]]
  topic_str <- if (is.character(topic_expr)) {
    topic_expr[[1L]]
  } else {
    paste(deparse(topic_expr), collapse = "")
  }
  pkg_expr <- cl[["package"]]
  pkg_str <- NULL
  if (!is.null(pkg_expr)) {
    pkg_str <- if (is.character(pkg_expr)) {
      pkg_expr[[1L]]
    } else {
      paste(deparse(pkg_expr), collapse = "")
    }
  }
  deephelp(topic_str, pkg_str)
}

# Drop-in replacement for utils::help.search()
shim_help_search <- function(pattern, ...) {
  if (!deephelp_enabled()) {
    return(utils::help.search(pattern, ...))
  }
  deephelp_search(pattern, ...)
}

# Drop-in replacement for the `?` operator
shim_question <- function(e1, e2) {
  e1_expr <- substitute(e1)
  is_vague <- is.call(e1_expr) && identical(e1_expr[[1L]], quote(`?`))
  if (!deephelp_enabled()) {
    return(eval(as.call(list(utils::`?`, substitute(e1), substitute(e2))),
                parent.frame()))
  }
  if (is_vague) {
    # ??pattern -> translated fuzzy search
    pat_expr <- e1_expr[[2L]]
    pattern <- if (is.character(pat_expr)) pat_expr[[1L]] else as.character(pat_expr)
    return(deephelp_search(pattern))
  }
  if (is.name(e1_expr)) {
    topic <- as.character(e1_expr)
    pkg <- NULL
  } else if (is.call(e1_expr)) {
    if (identical(e1_expr[[1L]], quote(`::`))) {
      topic <- as.character(e1_expr[[3L]])
      pkg <- as.character(e1_expr[[2L]])
    } else {
      topic <- deparse(e1_expr[[1L]])
      pkg <- NULL
    }
  } else if (is.character(e1_expr)) {
    topic <- e1_expr[[1L]]
    pkg <- NULL
  } else {
    return(eval(as.call(list(utils::`?`, substitute(e1), substitute(e2))),
                parent.frame()))
  }
  deephelp(topic, pkg)
}
