# Internal state and package load --------------------------------------------

.dh <- new.env(parent = emptyenv())

.dh$config <- list(
  api_key     = NULL,
  model       = "deepseek-flash",
  base_url    = "https://api.deepseek.com",
  lang        = "简体中文",
  cache       = NULL,   # NULL -> default cache dir; "" -> disabled; otherwise a path
  temperature = NULL,
  max_tokens  = NULL,
  timeout     = 120,
  cjk_spacing = TRUE,    # normalize spaces between CJK and Latin/digits ("pangu")
  glossary    = NULL     # NULL -> default glossary; character(0) -> none
)

# Bump this whenever the translation prompt or logic changes, to invalidate
# the on-disk cache.
.dh$schema <- "v18"

# Built-in statistics / R terminology glossary (English -> Simplified Chinese).
# Applied to natural-language prose only; never to code or identifiers.
.dh$default_glossary <- c(
  "regression"              = "回归",
  "linear regression"       = "线性回归",
  "logistic regression"     = "逻辑回归",
  "residual"                = "残差",
  "residuals"               = "残差",
  "variance"                = "方差",
  "standard deviation"      = "标准差",
  "standard error"          = "标准误",
  "mean"                    = "均值",
  "arithmetic mean"         = "算术平均值",
  "median"                  = "中位数",
  "coefficient"             = "系数",
  "intercept"               = "截距",
  "estimate"                = "估计值",
  "estimator"               = "估计量",
  "statistic"               = "统计量",
  "degrees of freedom"      = "自由度",
  "confidence interval"     = "置信区间",
  "confidence level"        = "置信水平",
  "hypothesis"              = "假设",
  "null hypothesis"         = "原假设",
  "alternative hypothesis"  = "备择假设",
  "p-value"                 = "p 值",
  "significance level"      = "显著性水平",
  "correlation"             = "相关性",
  "covariance"              = "协方差",
  "distribution"            = "分布",
  "normal distribution"     = "正态分布",
  "probability"             = "概率",
  "probability density"     = "概率密度",
  "density"                 = "密度",
  "sample"                  = "样本",
  "sampling"                = "抽样",
  "population"              = "总体",
  "observation"             = "观测值",
  "variable"                = "变量",
  "response variable"       = "响应变量",
  "predictor"               = "预测变量",
  "factor"                  = "因子",
  "level"                   = "水平",
  "interaction"             = "交互作用",
  "main effect"             = "主效应",
  "least squares"           = "最小二乘",
  "likelihood"              = "似然",
  "maximum likelihood"      = "最大似然",
  "bootstrap"               = "自助法",
  "resampling"              = "重抽样",
  "smoothing"               = "平滑",
  "clustering"              = "聚类",
  "classification"          = "分类",
  "outlier"                 = "离群值",
  "missing value"           = "缺失值",
  "weight"                  = "权重",
  "weights"                 = "权重",
  "matrix"                  = "矩阵",
  "vector"                  = "向量",
  "data frame"              = "数据框",
  "formula"                 = "公式",
  "fitting"                 = "拟合",
  "model"                   = "模型"
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
