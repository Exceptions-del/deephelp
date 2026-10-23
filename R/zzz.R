# Internal state and package load --------------------------------------------

.dh <- new.env(parent = emptyenv())

.dh$config <- list(
  api_key     = NULL,
  model       = "deepseek-flash",
  base_url    = "https://api.deepseek.com",
  lang        = "\u7b80\u4f53\u4e2d\u6587",
  cache       = NULL,   # NULL -> default cache dir; "" -> disabled; otherwise a path
  temperature = NULL,
  max_tokens  = NULL,
  timeout     = 120,
  cjk_spacing = TRUE,    # normalize spaces between CJK and Latin/digits ("pangu")
  glossary    = NULL     # NULL -> default glossary; character(0) -> none
)

# Bump this whenever the translation prompt or logic changes, to invalidate
# the on-disk cache.
.dh$schema <- "v21"

# Built-in statistics / R terminology glossary (English -> Simplified Chinese).
# Applied to natural-language prose only; never to code or identifiers.
.dh$default_glossary <- c(
  "regression"              = "\u56de\u5f52",
  "linear regression"       = "\u7ebf\u6027\u56de\u5f52",
  "logistic regression"     = "\u903b\u8f91\u56de\u5f52",
  "residual"                = "\u6b8b\u5dee",
  "residuals"               = "\u6b8b\u5dee",
  "variance"                = "\u65b9\u5dee",
  "standard deviation"      = "\u6807\u51c6\u5dee",
  "standard error"          = "\u6807\u51c6\u8bef",
  "mean"                    = "\u5747\u503c",
  "arithmetic mean"         = "\u7b97\u672f\u5e73\u5747\u503c",
  "median"                  = "\u4e2d\u4f4d\u6570",
  "coefficient"             = "\u7cfb\u6570",
  "intercept"               = "\u622a\u8ddd",
  "estimate"                = "\u4f30\u8ba1\u503c",
  "estimator"               = "\u4f30\u8ba1\u91cf",
  "statistic"               = "\u7edf\u8ba1\u91cf",
  "degrees of freedom"      = "\u81ea\u7531\u5ea6",
  "confidence interval"     = "\u7f6e\u4fe1\u533a\u95f4",
  "confidence level"        = "\u7f6e\u4fe1\u6c34\u5e73",
  "hypothesis"              = "\u5047\u8bbe",
  "null hypothesis"         = "\u539f\u5047\u8bbe",
  "alternative hypothesis"  = "\u5907\u62e9\u5047\u8bbe",
  "p-value"                 = "p \u503c",
  "significance level"      = "\u663e\u8457\u6027\u6c34\u5e73",
  "correlation"             = "\u76f8\u5173\u6027",
  "covariance"              = "\u534f\u65b9\u5dee",
  "distribution"            = "\u5206\u5e03",
  "normal distribution"     = "\u6b63\u6001\u5206\u5e03",
  "probability"             = "\u6982\u7387",
  "probability density"     = "\u6982\u7387\u5bc6\u5ea6",
  "density"                 = "\u5bc6\u5ea6",
  "sample"                  = "\u6837\u672c",
  "sampling"                = "\u62bd\u6837",
  "population"              = "\u603b\u4f53",
  "observation"             = "\u89c2\u6d4b\u503c",
  "variable"                = "\u53d8\u91cf",
  "response variable"       = "\u54cd\u5e94\u53d8\u91cf",
  "predictor"               = "\u9884\u6d4b\u53d8\u91cf",
  "factor"                  = "\u56e0\u5b50",
  "level"                   = "\u6c34\u5e73",
  "interaction"             = "\u4ea4\u4e92\u4f5c\u7528",
  "main effect"             = "\u4e3b\u6548\u5e94",
  "least squares"           = "\u6700\u5c0f\u4e8c\u4e58",
  "likelihood"              = "\u4f3c\u7136",
  "maximum likelihood"      = "\u6700\u5927\u4f3c\u7136",
  "bootstrap"               = "\u81ea\u52a9\u6cd5",
  "resampling"              = "\u91cd\u62bd\u6837",
  "smoothing"               = "\u5e73\u6ed1",
  "clustering"              = "\u805a\u7c7b",
  "classification"          = "\u5206\u7c7b",
  "outlier"                 = "\u79bb\u7fa4\u503c",
  "missing value"           = "\u7f3a\u5931\u503c",
  "weight"                  = "\u6743\u91cd",
  "weights"                 = "\u6743\u91cd",
  "matrix"                  = "\u77e9\u9635",
  "vector"                  = "\u5411\u91cf",
  "data frame"              = "\u6570\u636e\u6846",
  "formula"                 = "\u516c\u5f0f",
  "fitting"                 = "\u62df\u5408",
  "model"                   = "\u6a21\u578b"
)

# Memoized Rd databases, keyed by "<package>@<version>".
.dh$rd_db <- list()

# Rd tags whose contents must never be translated (code, links, math, ...).
.no_translate_tags <- c(
  "\\name", "\\alias", "\\keyword", "\\concept", "\\docType", "\\Rdversion",
  "\\encoding", "\\usage", "\\synopsis",
  "\\code", "\\preformatted", "\\verb", "\\kbd", "\\samp", "\\file",
  "\\command", "\\var", "\\env", "\\option", "\\pkg", "\\acronym", "\\dfn",
  "\\special", "\\out", "\\Sexpr",
  "\\link", "\\linkS4class", "\\url", "\\email", "\\href", "\\figure",
  "\\eqn", "\\deqn", "\\if", "\\ifelse", "\\method", "\\S3method", "\\S4method",
  "\\dontrun", "\\donttest", "\\dontshow", "\\testonly",
  "\\dots", "\\ldots", "\\cr", "\\tab", "\\R", "\\enc", "\\tabular",
  "\\newcommand", "\\renewcommand", "COMMENT", "USERMACRO"
)

`%||%` <- function(x, y) if (is.null(x)) y else x

# Stable md5 of a character vector (dependency-free, via tools::md5sum).
md5_char <- function(x) {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeLines(paste(x, collapse = "\n"), f, useBytes = TRUE)
  unname(tools::md5sum(f))
}

# Hash of translation-affecting settings (glossary + spacing), used to keep
# distinct cache entries when the user customizes them.
config_hash <- function(cfg) {
  gloss <- if (is.null(cfg$glossary)) .dh$default_glossary else cfg$glossary
  txt <- paste0(
    "cjk=", isTRUE(cfg$cjk_spacing),
    ";gloss=", paste(names(gloss), unname(gloss), sep = "\u0001", collapse = "\u0002")
  )
  md5_char(txt)
}

# Root cache directory (NULL when caching is disabled).
cache_root <- function(cfg) {
  if (!is.null(cfg$cache) && !nzchar(cfg$cache)) {
    return(NULL)
  }
  if (is.null(cfg$cache)) tools::R_user_dir("deephelp", "cache") else cfg$cache
}

.onLoad <- function(libname, pkgname) {
  tryCatch(attach_shims(), error = function(e) NULL)
  # R attaches the default packages (stats, utils, ...) at the very END of
  # startup, i.e. AFTER the user .Rprofile runs. A shim attached from .Rprofile
  # therefore ends up BELOW utils and would be shadowed. Re-attach the shims at
  # position 2 whenever `utils` is attached, which guarantees they always sit
  # above utils::help() / utils::?.
  tryCatch(
    setHook(
      packageEvent("utils", "attach"),
      function(...) attach_shims(),
      action = "replace"
    ),
    error = function(e) NULL
  )
  invisible()
}
