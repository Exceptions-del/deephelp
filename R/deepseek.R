# DeepSeek HTTP client ---------------------------------------------------------

deepseek_chat <- function(messages, config) {
  key <- resolve_api_key()
  if (!nzchar(key)) {
    stop(
      "No DeepSeek API key found. Set it with deephelp_use(api_key = \"...\"), ",
      "options(deephelp.api_key = \"...\"), or the DEEPSEEK_API_KEY environment variable.",
      call. = FALSE
    )
  }
  base <- sub("/+$", "", config$base_url)
  url <- paste0(base, "/chat/completions")

  body <- list(
    model    = config$model,
    messages = messages,
    stream   = FALSE,
    thinking = list(type = "disabled"),         # <-- turn reasoning OFF
    response_format = list(type = "json_object")
  )
  if (!is.null(config$temperature)) body$temperature <- config$temperature
  if (!is.null(config$max_tokens))  body$max_tokens  <- config$max_tokens

  resp <- httr::POST(
    url = url,
    httr::add_headers(
      Authorization = paste("Bearer", key),
      `Content-Type` = "application/json"
    ),
    body = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
    encode = "raw",
    httr::timeout(config$timeout %||% 120)
  )

  txt <- httr::content(resp, as = "text", encoding = "UTF-8")
  if (httr::http_error(resp)) {
    stop("DeepSeek API error (HTTP ", httr::status_code(resp), "): ", txt,
         call. = FALSE)
  }
  obj <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (is.null(obj$choices) || length(obj$choices) == 0L) {
    stop("DeepSeek API returned an empty response: ", txt, call. = FALSE)
  }
  msg <- obj$choices[[1L]]$message
  # If the API still returned a chain-of-thought, thinking mode was not
  # actually disabled. Warn so the user can see it.
  rc <- msg$reasoning_content
  if (!is.null(rc) && nzchar(paste(unlist(rc), collapse = ""))) {
    warning("deephelp: DeepSeek returned 'reasoning_content' (thinking mode may not be disabled).",
            call. = FALSE)
  }
  content <- msg$content
  if (is.null(content) || !nzchar(paste(unlist(content), collapse = ""))) {
    stop("DeepSeek API returned an empty 'content' field. Raw response: ", txt,
         call. = FALSE)
  }
  paste(unlist(content), collapse = "")
}
