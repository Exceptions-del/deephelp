# Vignette translation --------------------------------------------------------

# Drop-in replacement for utils::vignette(): wrap the returned object(s) so
# printing them routes through print.deephelp_vignette (which translates).
shim_vignette <- function(topic, package = NULL, lib.loc = NULL, all = TRUE) {
  v <- utils::vignette(topic, package = package, lib.loc = lib.loc, all = all)
  mark <- function(x) {
    if (inherits(x, "vignette")) {
      class(x) <- unique(c("deephelp_vignette", class(x)))
    }
    x
  }
  if (is.list(v) && !inherits(v, "vignette")) {
    for (i in seq_along(v)) {
      v[[i]] <- mark(v[[i]])
    }
  } else {
    v <- mark(v)
  }
  v
}

# S3 print method for translated vignettes.
print.deephelp_vignette <- function(x, ...) {
  fallback <- function() {
    class(x) <- setdiff(class(x), "deephelp_vignette")
    print(x)
  }
  if (!deephelp_enabled() || !nzchar(x$PDF) ||
      tolower(tools::file_ext(x$PDF)) != "html") {
    return(fallback())
  }
  html_file <- file.path(x$Dir, "doc", x$PDF)
  if (!file.exists(html_file)) {
    return(fallback())
  }
  tryCatch({
    out <- translate_vignette_html(html_file, .dh$config)
    if (requireNamespace("rstudioapi", quietly = TRUE) &&
        rstudioapi::isAvailable()) {
      rstudioapi::viewer(out)
    } else if (interactive()) {
      utils::browseURL(out)
    } else {
      fallback()
    }
  }, error = function(e) {
    warning("deephelp: vignette translation failed: ",
            conditionMessage(e), call. = FALSE)
    fallback()
  })
  invisible(x)
}

# Translate the prose of a rendered HTML vignette, preserving code blocks,
# inline code, links, images and math. Returns the path of the translated HTML.
translate_vignette_html <- function(html_file, cfg) {
  # Cached, self-contained translated HTML keyed by content + settings.
  cfile <- NULL
  root <- cache_root(cfg)
  if (!is.null(root)) {
    key <- md5_char(c(
      paste(readLines(html_file, warn = FALSE, encoding = "UTF-8"),
            collapse = "\n"),
      config_hash(cfg)
    ))
    cdir <- file.path(root, "_vignettes")
    dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
    cfile <- file.path(cdir, paste0(key, ".html"))
    if (file.exists(cfile)) {
      return(cfile)
    }
  }

  doc <- xml2::read_html(html_file)
  xpath <- paste0(
    "//body//text()[",
    "not(ancestor::pre) and not(ancestor::code) and ",
    "not(ancestor::script) and not(ancestor::style) and ",
    "not(ancestor::*[contains(@class, 'math')]) and ",
    "not(ancestor::*[contains(@class, 'katex')]) and ",
    "not(ancestor::*[contains(@class, 'mjx')])",
    "]"
  )
  nodes <- xml2::xml_find_all(doc, xpath)
  if (length(nodes) == 0L) {
    out <- if (is.null(cfile)) tempfile(fileext = ".html") else cfile
    xml2::write_html(doc, out)
    return(out)
  }

  raw <- xml2::xml_text(nodes)
  trimmed <- trimws(raw)
  keep <- nzchar(trimmed)
  if (any(keep)) {
    idx <- which(keep)
    translated <- translate_vignette_texts(trimmed[idx], cfg)
    # Preserve leading/trailing whitespace so spacing around inline <code>/<a>
    # is retained.
    lead <- sub("\\S.*$", "", raw[idx], perl = TRUE)
    trail <- sub(".*\\S", "", raw[idx], perl = TRUE)
    final <- paste0(lead, translated, trail)
    for (j in seq_along(idx)) {
      xml2::xml_text(nodes[[idx[j]]]) <- final[[j]]
    }
  }

  out <- if (is.null(cfile)) tempfile(fileext = ".html") else cfile
  xml2::write_html(doc, out)
  out
}

# Translate a character vector in chunks, sized by cumulative character count
# so that each request stays well within the model's output token limit.
translate_vignette_texts <- function(texts, cfg) {
  n <- length(texts)
  if (n == 0L) {
    return(character(0))
  }
  out <- character(n)
  budget <- 1200L
  start <- 1L
  cum <- 0L
  for (i in seq_len(n)) {
    cum <- cum + nchar(texts[i], type = "chars")
    if (cum >= budget && i > start) {
      out[start:i] <- translate_vignette_chunk(texts[start:i], cfg)
      start <- i + 1L
      cum <- 0L
    }
  }
  if (start <= n) {
    out[start:n] <- translate_vignette_chunk(texts[start:n], cfg)
  }
  out
}

translate_vignette_chunk <- function(texts, cfg) {
  failed <- FALSE
  tr <- withCallingHandlers(
    translate_batch(texts, cfg$lang, cfg),
    warning = function(w) {
      if (grepl("could not parse", conditionMessage(w))) {
        failed <<- TRUE
      }
      invokeRestart("muffleWarning")
    }
  )
  if (failed && length(texts) > 1L) {
    # Recursively split a failed batch in half and retry each part.
    mid <- ceiling(length(texts) / 2L)
    return(c(
      translate_vignette_chunk(texts[seq_len(mid)], cfg),
      translate_vignette_chunk(texts[seq.int(mid + 1L, length(texts))], cfg)
    ))
  }
  if (isTRUE(cfg$cjk_spacing)) {
    tr <- vapply(tr, cjk_spacing_text, character(1))
  }
  tr
}
