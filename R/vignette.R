# Vignette translation --------------------------------------------------------

# Inline elements: kept verbatim as [[INLINE:n]] placeholders inside a block's
# flattened prose so the model sees a complete sentence, not fragments split by
# inline <code>/<a>/<em> markup.
.vignette_inline_tags <- c(
  "a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "dfn", "em",
  "i", "img", "kbd", "mark", "q", "rp", "rt", "ruby", "s", "samp", "small",
  "span", "strong", "sub", "sup", "time", "u", "var", "wbr", "math", "mjx-container"
)

# Block elements whose text must never be translated.
.vignette_skip_tags <- c("script", "style", "pre")

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
      config_hash(cfg),
      .dh$schema
    ))
    cdir <- file.path(root, "_vignettes")
    dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
    cfile <- file.path(cdir, paste0(key, ".html"))
    if (file.exists(cfile)) {
      return(cfile)
    }
  }

  doc <- xml2::read_html(html_file)

  # Translate at the level of leaf prose blocks (paragraphs, headings, list
  # items, table cells), not individual text nodes. Translating node-by-node
  # sends the model sentence *fragments* split by inline <code>/<a> markup,
  # which makes it return interleaved English+Chinese. Flattening each block
  # (inline elements as [[INLINE:n]] placeholders) keeps sentences whole.
  blocks <- xml2::xml_find_all(doc, "//body//*[text()[normalize-space()]]")
  nm <- xml2::xml_name(blocks)
  blocks <- blocks[!(nm %in% .vignette_inline_tags) & !(nm %in% .vignette_skip_tags)]
  if (length(blocks) == 0L) {
    out <- if (is.null(cfile)) tempfile(fileext = ".html") else cfile
    xml2::write_html(doc, out)
    return(out)
  }

  flats <- lapply(blocks, flatten_html_block)
  texts <- vapply(flats, `[[`, character(1), "text")
  keep <- nzchar(trimws(texts))
  if (any(keep)) {
    idx <- which(keep)
    translated <- translate_vignette_texts(texts[idx], cfg)
    for (j in seq_along(idx)) {
      rebuild_html_block(flats[[idx[j]]], translated[[j]])
    }
  }

  out <- if (is.null(cfile)) tempfile(fileext = ".html") else cfile
  xml2::write_html(doc, out)
  out
}

# Flatten one block element's direct children into a single prose string. Text
# children become translatable pieces (whitespace runs collapsed to one space,
# matching HTML rendering); inline children become [[INLINE:n]] markers and are
# left untouched in the document. Nested block children are skipped here because
# they are selected and translated as blocks themselves.
flatten_html_block <- function(el) {
  kids <- xml2::xml_contents(el)
  parts <- character()
  text_nodes <- list()
  n_inline <- 0L
  for (k in kids) {
    ty <- xml2::xml_type(k)
    if (identical(ty, "text")) {
      collapsed <- gsub("[ \t\r\n]+", " ", xml2::xml_text(k), perl = TRUE)
      parts <- c(parts, collapsed)
      text_nodes[[length(text_nodes) + 1L]] <- k
    } else if (identical(ty, "element") &&
               xml2::xml_name(k) %in% .vignette_inline_tags) {
      n_inline <- n_inline + 1L
      parts <- c(parts, sprintf("[[INLINE:%d]]", n_inline))
    }
  }
  list(text = paste(parts, collapse = ""), text_nodes = text_nodes)
}

# Write a translated block string back into the block's text children, in order.
# [[INLINE:n]] markers are used only to split the translation; the inline
# elements they represented are already in the document and are left as-is.
rebuild_html_block <- function(flat, translated) {
  nn <- length(flat$text_nodes)
  if (nn == 0L) {
    return(invisible(NULL))
  }
  token_pat <- "\\[\\[INLINE:[0-9]+\\]\\]"
  m <- gregexpr(token_pat, translated, perl = TRUE)[[1L]]
  if (m[[1L]] == -1L) {
    pieces <- translated
  } else {
    lens <- attr(m, "match.length")
    pieces <- character()
    pos <- 1L
    for (j in seq_along(m)) {
      pieces <- c(pieces, substr(translated, pos, m[[j]] - 1L))
      pos <- m[[j]] + lens[[j]]
    }
    pieces <- c(pieces, substr(translated, pos, nchar(translated)))
  }
  for (i in seq_len(nn)) {
    val <- if (i <= length(pieces)) pieces[[i]] else ""
    xml2::xml_text(flat$text_nodes[[i]]) <- val
  }
  invisible(NULL)
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
