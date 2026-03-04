# Code Analysis

代码阅读、分析、导航场景必须优先使用 LSP 工具（search_symbols, find_references, goto_definition, get_hover 等），而非 grep/fs_read 逐行搜索。

理由：LSP 提供语义级分析（类型、引用链、定义跳转），grep 只做文本匹配，容易漏掉或误匹配。

适用：
- 查找符号定义/引用 → search_symbols + find_references
- 理解类型/签名 → get_hover
- 文件结构概览 → get_document_symbols
- 架构理解 → generate_codebase_overview
- 调试/debug → get_diagnostics 为首选工具，获取编译器错误和警告后再用 search_symbols + find_references 定位根因

冷启动：
- 进入代码密集项目（含 .py/.ts/.rs 等）时，先执行 initialize_workspace 初始化 LSP，确保后续工具可用

探索阶段：
- 深入具体文件前，先用 generate_codebase_overview 获取项目全貌

结构化搜索：
- 查找代码模式（如所有错误处理、所有 API 调用）→ pattern_search，而非 grep
- pattern_search 基于 AST，能匹配结构而非文本

安全代码变换：
- 结构化代码替换 → pattern_rewrite（先 dry_run 预览），替代 sed
- 动机：sed 操作 JSON/代码易破坏结构（block-sed-json.sh hook 会拦截）

python pattern 注意事项：
- `def $FUNC($$$):` 不工作，需写成 `def $FUNC($$$ARGS): $$$BODY`
- python 的 ast-grep pattern 必须包含函数体占位符

例外：
- 搜索注释/字符串中的文本 → grep
- 读取非代码文件（markdown、config）→ fs_read
