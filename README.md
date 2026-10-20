# deephelp

[![Version](https://img.shields.io/badge/version-0.3.2-blue.svg)](https://github.com/Exceptions-del/deephelp)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

用 [DeepSeek](https://www.deepseek.com/) 把 R 帮助文档**即时翻译成中文**的 R 包。

加载后，`?` 和 `help()` 会被无缝替换：`?lm`、`help("mean")`、`?dplyr::mutate` 会自动弹出**中文版帮助页**，显示在 **Help 面板**（支持 **RStudio** 与 **Positron**）。

## 特性

- **无感替换**：`?`、`help()`、`help.search()`、`vignette()` 自动生效，无需改调用方式
- **强制关闭推理**：每次请求都发送 `thinking: disabled`，翻译干净、快、省 token
- **只译文字、不碰代码**：`\code{}`、`\link{}`、`\usage{}`、公式、以及示例里的 **R 代码本身**保持原样；示例里的 `#` 注释会一并翻译
- **保留版式**：用占位标记还原原文的段落与换行，译文排版与原文一致
- **盘古之白**：中英文/数字之间自动补空格
- **磁盘缓存**：同一主题二次查看零 token
- **术语表**：内置约 60 条统计/R 术语，保证翻译一致

## 与 [lang](https://github.com/mlverse/lang) 的区别

`deephelp` 参考了 `lang`，但专门解决一个问题：**关闭 DeepSeek 的推理（thinking）模式**。DeepSeek 新版 API 默认开启思考模式，`lang` 无法关闭它，导致翻译混入推理文本、等待久、费 token。`deephelp` 每次请求硬编码：

```json
{ "thinking": { "type": "disabled" } }
```

并默认使用非推理模型 `deepseek-flash`（最快最省）。

| | lang | deephelp |
|---|---|---|
| 关闭推理 | 无法传 `thinking: disabled` | 每次请求强制关闭 |
| 默认模型 | 取决于 mall 配置 | `deepseek-flash`（非推理） |
| 结果 | 可能混入推理、慢、费 token | 干净、快、省 token |

## 安装

依赖 R >= 4.1，`httr` 与 `jsonlite`（安装时自动拉取），`rstudioapi` 可选（在 RStudio/Positron 中用于渲染到 Help 面板）。

```r
# 从 GitHub 安装
remotes::install_github("Exceptions-del/deephelp")
# 或
pak::pak("Exceptions-del/deephelp")

# 从本地源码目录安装
install.packages("path/to/deephelp", repos = NULL, type = "source")
```

## 快速开始

```r
library(deephelp)

# 配置 API Key（任选其一）
deephelp_use(api_key = "sk-xxxx")          # 方式 1：参数
# options(deephelp.api_key = "sk-xxxx")    # 方式 2：R 选项
# 方式 3：在 .Renviron 里写 DEEPSEEK_API_KEY=sk-xxxx

?lm              # 自动显示中文帮助
?dplyr::mutate   # 指定包
help("mean")     # 等价于 ?mean
```

常用开关：

```r
deephelp_off()                       # 临时切回英文原版
deephelp_on()                        # 再开启
deephelp("lm", type = "text")        # 纯文本输出
deephelp_clear_cache()               # 清空翻译缓存
deephelp_status()                    # 查看当前配置
```

## 配置

```r
deephelp_use(
  api_key     = "sk-xxxx",
  model       = "deepseek-flash",        # 默认：最快最省的非推理模型
  base_url    = "https://api.deepseek.com",
  lang        = "简体中文",
  cache       = "D:/my_cache",           # 或 "" 关闭缓存
  timeout     = 120,
  max_tokens  = 8000,
  cjk_spacing = TRUE,                    # 中西文之间自动加空格（盘古之白）
  glossary    = c("regression" = "回归", # 在默认术语表上覆盖/追加
                  "residual"   = "残差")
)
```

| 参数 | 说明 |
|---|---|
| `api_key` | DeepSeek API Key；回退到 `getOption("deephelp.api_key")` 与 `DEEPSEEK_API_KEY` 环境变量 |
| `model` | 默认 `"deepseek-flash"`；高质量可改 `"deepseek-v4-pro"` |
| `lang` | 目标语言，默认 `"简体中文"` |
| `cache` | 缓存目录；`NULL` 用默认位置，`""` 关闭缓存 |
| `cjk_spacing` | 是否在中文与英文/数字间补空格，默认 `TRUE` |
| `glossary` | 命名字符向量，在默认术语表上覆盖/追加；`character(0)` 关闭术语表 |

## 支持的环境

| 环境 | 翻译页显示 | 说明 |
|---|---|---|
| RStudio | ✅ | Help 面板，`\link{}` 可跳转到英文原版 |
| Positron | ✅ | Help 面板；跨页跳转受限（见下） |
| 其它（终端等） | ⚠️ | 自动回退为纯文本 |

### Positron 注意事项

Positron 的 Help 面板通过 ark 帮助代理转发链接，遇到 R 帮助服务器的 302 重定向会返回 502，因此**翻译页里的 `\link{}` 跨页跳转在 Positron 上不可用**（这是 Positron 自身的限制，非 deephelp 的问题）。

另外，部分 Windows 版 Positron 会把环境变量 `R_SHARE_DIR` 写成带 `Active code page: 65001` 前缀的脏值，导致帮助页（甚至时区）加载失败。症状为 `?` 时提示 `cannot open file ... system.Rd`，且 `R.home("share")` 返回带该前缀的值。修复方法是在 `~/.Renviron` 里显式写回正确路径：

```sh
R_SHARE_DIR="D:/R-4.5.3/share"     # 改成你的 R 安装路径
R_DOC_DIR="D:/R-4.5.3/doc"
R_INCLUDE_DIR="D:/R-4.5.3/include"
```

然后重启 Positron 的 R 内核。

## 工作原理

1. 加载时（`.onLoad`）把改写过的 `help`/`?` attach 到搜索路径第 2 位，并注册 `utils` attach 钩子保证它们始终优先于 `utils::help`/`utils::?`
2. 用 `utils::help(..., help_type = "text")` 定位真正的 Rd 文件与包名（自动解析别名，如 `geom_col` → `geom_bar`）
3. 用 `tools::Rd_db()` 得到已解析的 Rd 对象，只遍历并翻译文本节点，代码/链接/公式/用法一律保留；示例里的 `#` 注释单独翻译，字符串里的 `#` 会正确跳过
4. 用 `[[PARA]]`/`[[BR]]` 标记保留段落与换行，翻译后按标记还原版式
5. 所有文本去重后合并成**一次** DeepSeek 请求（JSON 对齐回填），结果写回解析树
6. 翻译后的解析树写入临时“伪包”目录，用 `rstudioapi::previewRd()` 显示到 Help 面板
7. 按「包名/主题/版本/模型/语言」缓存到 `tools::R_user_dir("deephelp", "cache")`，二次查看零 token

## 已知限制

- **不做“跳转翻译”**：点击翻译页里的 `\link{}` 跳到的是对应帮助页（英文原版），目标页不会自动翻译；Positron 上跨页跳转本身不可用
- Help 面板里的 “Run examples” 链接在预览页中指向的相对路径不可用（该链接由渲染器现场生成，不在 Rd 源码内）
- 翻译质量取决于模型，术语一致性依赖内置术语表

## License

[MIT](LICENSE)
