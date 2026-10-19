# Rd translation ---------------------------------------------------------------

# Inline macros whose content is kept verbatim and turned into a placeholder
# inside a prose block (so a sentence spanning several inline macros is still
# translated as ONE unit).
.inline_tags <- c(
  "\\code", "\\link", "\\linkS4class", "\\url", "\\email", "\\pkg",
  "\\env", "\\option", "\\file", "\\samp", "\\kbd", "\\verb", "\\var",
  "\\command", "\\acronym", "\\dfn", "\\eqn", "\\deqn", "\\special",
  "\\out", "\\Sexpr", "\\href", "\\figure", "\\method", "\\S3method",
  "\\S4method", "\\dots", "\\ldots", "\\cr", "\\tab", "\\R", "\\enc",
  "\\sQuote", "\\dQuote"
)

# Top-level sections whose whole prose content is translated as one block.
.prose_tags <- c(
  "\\title", "\\description", "\\details", "\\note", "\\author",
  "\\references", "\\seealso", "\\source"
)

# Formatting macros whose content is still translatable: we recurse into them
# (the emphasis itself is dropped, but the text is translated). "LIST" is the
# anonymous-list node that holds the text of an \itemize/\enumerate bullet.
.transparent_tags <- c("\\emph", "\\strong", "\\bold", "\\cite", "\\abbr", "LIST")

rd_translate <- function(rd, lang, config) {
  state <- new.env(parent = emptyenv())
  state$mode <- "collect"
  state$out <- list()      # one flattened string per prose block
  state$inline <- list()   # per block: list of inline macro subtrees
  state$cjk_spacing <- isTRUE(config$cjk_spacing)
  rd_walk(rd, state)

  if (length(state$out) == 0L) {
    return(rd)
  }

  translated <- translate_batch(unlist(state$out), lang, config)

  state$mode <- "apply"
  state$i <- 0L
  state$translations <- translated
  rd_walk(rd, state)
}

rd_walk <- function(x, state) {
  tag <- attr(x, "Rd_tag")
  if (!is.list(x)) {
    # Leaf node (TEXT / VERB / RCODE / COMMENT / ...): keep verbatim. Real
    # prose is handled at block level inside prose_block(), not here.
    return(x)
  }
  if (!is.null(tag) && tag %in% .no_translate_tags) {
    return(x)
  }
  if (is.null(tag)) {
    for (i in seq_along(x)) {
      x[[i]] <- rd_walk(x[[i]], state)
    }
    return(x)
  }
  if (tag %in% .prose_tags) {
    # Use items_section (not prose_block) so nested block structures such as
    # \subsection / \itemize / \describe inside the section are recursed into.
    return(items_section(x, state))
  }
  if (tag %in% c("\\section", "\\subsection")) {
    x[[1L]] <- items_section(x[[1L]], state)
    x[[2L]] <- items_section(x[[2L]], state)
    return(x)
  }
  if (identical(tag, "\\examples")) {
    return(examples_child(x, state))
  }
  if (identical(tag, "\\item")) {
    if (length(x) >= 2L && is.list(x[[1L]]) && is.list(x[[2L]])) {
      # arguments/value/describe/format style: \item{label}{description}.
      # Use items_section (not prose_block) so nested block lists such as
      # \itemize / \enumerate inside the description are recursed into and
      # their bullet text is translated too.
      x[[2L]] <- items_section(x[[2L]], state)
    } else {
      # itemize/enumerate style: \item{text} where the whole content is prose
      # (possibly interleaved with inline \code / \link nodes).
      x <- items_section(x, state)
    }
    return(x)
  }
  if (tag %in% c("\\arguments", "\\value", "\\describe", "\\format",
                 "\\itemize", "\\enumerate")) {
    return(items_section(x, state))
  }
  for (i in seq_along(x)) {
    x[[i]] <- rd_walk(x[[i]], state)
  }
  x
}

# Sections that mix structured block nodes with plain prose: the intro/outro
# text of \value, the item list of \arguments/\describe, and the \format data
# frame layout (intro prose + \describe of column descriptions). Consecutive
# non-structural children are grouped into one prose block; structural children
# (\item, \describe, \itemize, \enumerate) are recursed into and translated.
whitespace_only <- function(seg) {
  all(vapply(seg, function(ch) {
    tg <- attr(ch, "Rd_tag")
    (is.null(tg) || identical(tg, "TEXT")) &&
      !nzchar(trimws(paste(as.character(ch), collapse = "")))
  }, logical(1)))
}

items_section <- function(node, state) {
  is_item <- vapply(node, function(ch) {
    tg <- attr(ch, "Rd_tag")
    !is.null(tg) && tg %in% c("\\item", "\\describe", "\\itemize", "\\enumerate",
                              "\\section", "\\subsection",
                              "COMMENT", "USERMACRO", "\\newcommand", "\\renewcommand",
                              "\\tabular", "\\preformatted")
  }, logical(1))
  out <- list()
  r <- 1L
  while (r <= length(node)) {
    if (is_item[[r]]) {
      out[[length(out) + 1L]] <- rd_walk(node[[r]], state)
      r <- r + 1L
    } else {
      run <- r
      while (run <= length(node) && !is_item[[run]]) {
        run <- run + 1L
      }
      seg <- node[seq.int(r, run - 1L)]
      if (whitespace_only(seg)) {
        # Keep blank-line separators verbatim: a `%` comment must stay on its
        # own line, otherwise it would swallow the following Rd markup.
        out <- c(out, seg)
      } else if (state$mode == "collect") {
        flat <- flatten(seg)
        state$out[[length(state$out) + 1L]] <- flat$text
        state$inline[[length(state$inline) + 1L]] <- flat$inline
        out <- c(out, seg)
      } else {
        state$i <- state$i + 1L
        out <- c(out, rebuild(state$inline[[state$i]],
                              state$translations[[state$i]],
                              cjk_spacing = state$cjk_spacing))
      }
      r <- run
    }
  }
  attributes(out) <- attributes(node)
  out
}

# Translate one prose block.
prose_block <- function(node, state) {
  if (!is.list(node)) {
    node <- list(node)
  }
  att <- attributes(node)
  if (state$mode == "collect") {
    flat <- flatten(node)
    state$out[[length(state$out) + 1L]] <- flat$text
    state$inline[[length(state$inline) + 1L]] <- flat$inline
    return(node)
  }
  state$i <- state$i + 1L
  out <- rebuild(state$inline[[state$i]], state$translations[[state$i]],
                 cjk_spacing = state$cjk_spacing)
  attributes(out) <- att
  out
}

# Flatten a list of Rd children into one string. Inline macros become
# [[INLINE:n]] placeholders (the macros are kept for rebuilding); blank lines
# become [[PARA]] markers.
flatten <- function(node) {
  parts <- character()
  inline <- list()

  rec <- function(ch) {
    t <- attr(ch, "Rd_tag")
    if (is.null(t) || identical(t, "TEXT")) {
      if (is.character(ch)) {
        parts <<- c(parts, paste(as.character(ch), collapse = "\n"))
      } else {
        for (cc in ch) {
          rec(cc)
        }
      }
    } else if (t %in% .inline_tags) {
      k <- length(inline) + 1L
      inline[[k]] <<- ch
      parts <<- c(parts, sprintf("[[INLINE:%d]]", k))
    } else if (t %in% .transparent_tags) {
      for (cc in ch) {
        rec(cc)
      }
    } else {
      # Any other macro (e.g. expanded \doi, \if, USERMACRO, ...) kept verbatim.
      k <- length(inline) + 1L
      inline[[k]] <<- ch
      parts <<- c(parts, sprintf("[[INLINE:%d]]", k))
    }
  }
  for (ch in node) {
    rec(ch)
  }

  # Join with "" (not "\n"): the TEXT leaves already carry their own trailing
  # newlines, so a plain join reproduces the source line/blank-line structure.
  text <- paste(parts, collapse = "")
  # Collapse horizontal whitespace only (keep newlines), then trim the ends.
  text <- gsub("[ \t]+", " ", text, perl = TRUE)
  text <- gsub("^[ \n]+", "", text, perl = TRUE)
  text <- gsub("[ \n]+$", "", text, perl = TRUE)
  # Blank lines -> paragraph break; single newlines -> line break. Both are kept
  # as explicit markers so the model preserves the original line structure.
  text <- gsub("\n[ ]*\n+", " [[PARA]] ", text, perl = TRUE)
  text <- gsub("\n[ ]*", " [[BR]] ", text, perl = TRUE)
  text <- gsub(" {2,}", " ", text, perl = TRUE)
  list(text = text, inline = inline)
}

# Rebuild a list of Rd children from a translated string, restoring inline
# macros at their [[INLINE:n]] positions. [[PARA]] markers are turned into
# separate blank-line TEXT nodes so the renderer produces real paragraph breaks.
rebuild <- function(inline, translated, cjk_spacing = FALSE) {
  n <- length(inline)
  out <- list()
  restored <- rep(FALSE, n)
  # Markers: [[INLINE:k]] restores an inline macro; [[PARA]] / [[BR]] restore
  # paragraph / line breaks so the translated page keeps the original layout.
  token_pat <- "\\[\\[(PARA|BR|INLINE:[0-9]+)\\]\\]"

  emit_text <- function(txt) {
    txt <- trimws(txt)
    if (nzchar(txt)) {
      out[[length(out) + 1L]] <<- structure(txt, Rd_tag = "TEXT")
    }
  }
  emit_break <- function(blank) {
    # Rd2HTML detects a paragraph break via isBlankLineRd(): the TEXT node must
    # be a blank line (content starting with "\n") AND its srcref[2] (first
    # byte) must equal 1. A soft line break is a plain "\n" node without srcref,
    # which HTML renders as a single space.
    #
    # For a real paragraph break we emit TWO newlines ("\n\n"): this both lets
    # Rd2HTML render a paragraph break AND survives Rd-source serialization
    # (srcref is dropped when deparsing, so "\n" alone would collapse back to a
    # soft break).
    node <- structure(if (blank) "\n\n" else "\n", Rd_tag = "TEXT")
    if (blank) {
      attr(node, "srcref") <- structure(c(1L, 1L, 1L, 1L, 1L, 1L), class = "srcref")
    }
    out[[length(out) + 1L]] <<- node
  }

  m <- gregexpr(token_pat, translated, perl = TRUE)[[1L]]
  pos <- 1L
  if (m[[1L]] != -1L) {
    lens <- attr(m, "match.length")
    for (j in seq_along(m)) {
      start <- m[[j]]
      len <- lens[[j]]
      emit_text(substr(translated, pos, start - 1L))
      tok <- substr(translated, start, start + len - 1L)
      kind <- sub("\\[\\[(.*)\\]\\]", "\\1", tok)
      if (identical(kind, "PARA")) {
        emit_break(TRUE)
      } else if (identical(kind, "BR")) {
        emit_break(FALSE)
      } else if (startsWith(kind, "INLINE:")) {
        key <- as.integer(sub("^INLINE:", "", kind))
        if (!is.na(key) && key >= 1L && key <= n) {
          out[[length(out) + 1L]] <- inline[[key]]
          restored[[key]] <- TRUE
        }
      }
      pos <- start + len
    }
  }
  emit_text(substr(translated, pos, nchar(translated)))

  # Append any inline nodes whose placeholder the model dropped.
  for (k in which(!restored)) {
    out[[length(out) + 1L]] <- inline[[k]]
  }
  if (length(out) == 0L) {
    out <- list(structure("", Rd_tag = "TEXT"))
  }
  if (cjk_spacing) {
    out <- cjk_spacing_nodes(out)
  }
  out
}

# Normalize pangu spacing inside a single plain string: insert one space between
# CJK and Latin/digit characters (both directions).
cjk_spacing_text <- function(x) {
  cjk <- "[\u4e00-\u9fff\u3400-\u4dbf]"
  lat <- "[A-Za-z0-9]"
  x <- gsub(paste0("(", cjk, ")(", lat, ")"), "\\1 \\2", x, perl = TRUE)
  x <- gsub(paste0("(", lat, ")(", cjk, ")"), "\\1 \\2", x, perl = TRUE)
  x
}

# Insert consistent single spaces between CJK characters and Latin letters /
# digits, and between CJK text and adjacent inline nodes (code, links, math).
# This deterministically normalizes the "pangu" spacing that the model may emit
# inconsistently.
cjk_spacing_nodes <- function(nodes) {
  cjk <- "[\u4e00-\u9fff\u3400-\u4dbf]"
  is_text <- vapply(nodes, function(z) identical(attr(z, "Rd_tag"), "TEXT"),
                    logical(1))
  for (i in seq_along(nodes)) {
    if (!is_text[[i]]) next
    val <- as.character(nodes[[i]])
    if (length(val) != 1L || !nzchar(trimws(val))) next  # skip blank break nodes
    val <- cjk_spacing_text(val)
    if (i > 1L && !is_text[[i - 1L]] &&
        grepl(paste0("^", cjk), val, perl = TRUE)) {
      val <- paste0(" ", val)
    }
    if (i < length(nodes) && !is_text[[i + 1L]] &&
        grepl(paste0(cjk, "$"), val, perl = TRUE)) {
      val <- paste0(val, " ")
    }
    new_node <- structure(val, Rd_tag = "TEXT")
    sr <- attr(nodes[[i]], "srcref")
    if (!is.null(sr)) attr(new_node, "srcref") <- sr
    nodes[[i]] <- new_node
  }
  nodes
}

# Split one line of R code at the first `#` that is not inside a string literal.
# Returns list(code, comment) or NULL when the line has no comment.
split_code_comment <- function(line) {
  chars <- strsplit(line, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  if (n == 0L) return(NULL)
  in_str <- NA_character_
  i <- 1L
  while (i <= n) {
    ch <- chars[[i]]
    if (is.na(in_str)) {
      if (ch == '"' || ch == "'") {
        in_str <- ch
      } else if (ch == '#') {
        if (i == 1L || chars[[i - 1L]] %in% c(' ', '\t')) {
          return(list(code = substr(line, 1L, i - 1L),
                      comment = substr(line, i, nchar(line))))
        }
      }
    } else if (ch == '\\') {
      i <- i + 1L
    } else if (ch == in_str) {
      in_str <- NA_character_
    }
    i <- i + 1L
  }
  NULL
}

# Translate the `#` comment in one RCODE line, keeping the code verbatim.
translate_example_code <- function(code, state) {
  res <- split_code_comment(code)
  if (is.null(res)) return(code)
  comment_text <- sub("^#+\\s*", "", res$comment)
  if (!nzchar(trimws(comment_text))) return(code)
  if (state$mode == "collect") {
    state$out[[length(state$out) + 1L]] <- comment_text
    state$inline[[length(state$inline) + 1L]] <- list()
    return(code)
  }
  state$i <- state$i + 1L
  translated <- state$translations[[state$i]]
  if (isTRUE(state$cjk_spacing)) translated <- cjk_spacing_text(translated)
  prefix <- substr(res$comment, 1L, nchar(res$comment) - nchar(comment_text))
  paste0(res$code, prefix, translated)
}

# Recursively translate `#` comments inside \examples (including \dontrun /
# \donttest / \dontshow / \testonly wrappers); the R code stays verbatim.
examples_child <- function(x, state) {
  if (is.character(x)) {
    tag <- attr(x, "Rd_tag")
    if (is.null(tag) || identical(tag, "RCODE")) {
      out <- x
      for (j in seq_along(x)) out[[j]] <- translate_example_code(x[[j]], state)
      return(out)
    }
    return(x)
  }
  if (is.list(x)) {
    for (i in seq_along(x)) x[[i]] <- examples_child(x[[i]], state)
    return(x)
  }
  x
}

translate_batch <- function(texts, lang, config) {
  if (length(texts) == 0L) {
    return(character(0))
  }
  keep <- nzchar(trimws(texts))
  if (!any(keep)) {
    return(texts)
  }
  uniq <- unique(texts[keep])

  gloss <- config$glossary %||% .dh$default_glossary
  gloss_str <- if (length(gloss) > 0L) {
    paste0(
      "\n\nTerminology glossary. Apply ONLY to natural-language prose ",
      "(never to R code, function/argument names or technical identifiers). ",
      "Prefer these translations when the term appears:\n",
      paste0("- ", names(gloss), " = ", unname(gloss), collapse = "\n")
    )
  } else {
    ""
  }

  sys <- paste0(
    "You are a professional technical translator for R documentation. ",
    "Translate each string in the provided JSON array into ", lang,
    " (Simplified Chinese).\n",
    "Rules:\n",
    "1. Translate only natural-language prose. Keep ALL R code, function names, ",
    "argument/parameter names, package names, object/class names, file paths, ",
    "URLs and technical identifiers unchanged in English.\n",
    "2. Preserve any [[PARA]], [[BR]] and [[INLINE:n]] marker exactly as-is. ",
    "Do not merge, split, translate, reorder or drop them.\n",
    "3. Do not add explanations, notes or extra text. Output translations only.\n",
    "4. Return a JSON object {\"translations\": [\"...\", \"...\"]} with EXACTLY ",
    length(uniq), " strings, in the same order.",
    gloss_str
  )
  usr <- paste0(
    "Translate the strings in the JSON array below. Return only ",
    "{\"translations\": [\"...\", \"...\"]} with the same number of strings ",
    "and the same order:\n\n",
    jsonlite::toJSON(uniq, auto_unbox = TRUE)
  )

  translated_uniq <- NULL
  for (attempt in 1:2) {
    content <- deepseek_chat(
      list(
        list(role = "system", content = sys),
        list(role = "user", content = usr)
      ),
      config
    )
    translated_uniq <- parse_translation_array(content, length(uniq))
    if (!is.null(translated_uniq)) {
      break
    }
    if (attempt == 1L) {
      usr <- paste0(usr, "\n\nIMPORTANT: return EXACTLY ", length(uniq),
                    " strings. Do not merge or split any string.")
    }
  }

  if (is.null(translated_uniq)) {
    warning("deephelp: could not parse the DeepSeek response (expected ",
            length(uniq), " items); showing the original text.\n",
            "Raw response (first 500 chars): ",
            substr(as.character(content), 1L, 500L),
            call. = FALSE)
    return(texts)
  }

  result <- texts
  result[keep] <- translated_uniq[match(texts[keep], uniq)]
  result
}

parse_translation_array <- function(content, n) {
  if (is.null(content) || !nzchar(content)) {
    return(NULL)
  }
  txt <- as.character(content)
  txt <- sub("^```[a-zA-Z]*\\s*", "", txt)
  txt <- sub("\\s*```$", "", txt)

  obj <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = TRUE),
                  error = function(e) NULL)
  if (is.null(obj)) {
    m <- regexpr("\\{.*\\}|\\[.*\\]", txt, perl = TRUE)
    if (m[[1L]] > 0L) {
      obj <- tryCatch(jsonlite::fromJSON(regmatches(txt, m), simplifyVector = TRUE),
                      error = function(e) NULL)
    }
  }
  if (is.null(obj)) {
    return(NULL)
  }
  if (is.list(obj) && !is.null(obj[["translations"]])) {
    obj <- obj[["translations"]]
  }
  if (length(obj) != n) {
    return(NULL)
  }
  as.character(obj)
}
