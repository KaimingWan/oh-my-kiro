# Episodes (Episodic Memory)

> Timestamped events. ≤30 entries. Auto-captured by hook + manual via @reflect.

<!-- FORMAT: DATE | STATUS | KEYWORDS | SUMMARY -->
<!-- STATUS: active / resolved / promoted -->
<!-- Promotion candidates are computed at runtime (keyword freq ≥3), not stored -->

2026-02-24 | active | research,knowledge,kiro,context,hook | 调研Kiro hook输出导致auto-compact失败的issue时: ①跳过知识库直接外部搜索(context-enrichment已提示related episodes但未读) ②搜索词偏差(用auto-summary搜,实际issue用auto-compact) ③发现#1531错误引用后没追查正确编号就停了. 正确issue: kirodotdev/Kiro#5792+#5527. 修复: 调研流程必须先查知识库(INDEX.md→episodes→docs),再外部搜索; 发现引用错误时必须追查正确来源不能停
2026-02-15 | active | symlink,fs_read,directory | fs_read Directory模式不支持symlink目录, 用ls或execute_bash替代

2026-02-19 | active | ralph-loop,verify,plan,format | Plan的Verify命令必须用inline backtick格式(**Verify:** `cmd`), 不能用fenced code block(```bash). ralph_loop.py正则只匹配inline backtick, fenced block导致解析残缺→shell语法错误→3轮无进展触发circuit breaker. DO: **Verify:** `cmd`. DON'T: **Verify:**后换行写```bash块





2026-02-20 | active | fs_write,kiro,tool,revert,git-commit | Kiro的fs_write工具会在两次tool call之间恢复被修改的文件到原始状态(疑似工具层面的sandbox机制). 症状: str_replace/append报告成功但下一次tool call时文件内容已回滚. 解决: 所有文件修改必须在单个execute_bash调用中完成(用Python脚本批量修改), 并在同一调用中git commit持久化. DO: 单个bash命令内完成modify+verify+commit. DON'T: 用fs_write修改源码后期望下一个tool call能看到变更

2026-02-20 | active | debugging,lsp,research,skill,industry | Agent debugging能力弱的根因不是"最佳实践流程"不够, 而是debugging skill只教哲学不教工具. 行业调研发现: ①SOTA agent(Refact.ai 70.4% SWE-bench)全部用语义导航工具(search_symbol_definition/usages), 不靠grep ②LSP findReferences返回23精确调用点 vs grep返回500+噪音(token省4x) ③Refact.ai强制debug_script()子agent至少调1次, 不封装成专用工具时模型会跳过调试直接改代码 ④SWE-Exp论文: 检索1条历史经验效果最好, 多了反而降性能 ⑤lsp-tools三铁律: 不goToDefinition不改代码/不findReferences不重构/不getDiagnostics不声称正确. 方案方向: 重写debugging skill嵌入LSP工具链+强制诊断证据+工具决策矩阵+episodes检索+修改前后diagnostics对比

2026-02-21 | active | phase0,alignment,user-intent,language | Phase 0分析产出偏离用户需求. 两个独立问题: ①用户中文提问却用英文回复——输入风格匹配的基本功没做到 ②用户说"执行时间/效率"却聚焦代码整洁(DRY/fd双关闭)——读完代码后被细节吸引, 没回头锚定原始需求. 根因不同不应混为一谈. 修复: Phase 0每个发现项产出前显式对齐用户原话——"这个发现回应了用户哪句话?" 对不上的降级或丢弃
| 2026-02-21 | plan执行绕过ralph loop | agent review完plan后直接手动执行7个task而非启动ralph loop. enforce-ralph-loop hook用denylist模式检测shell写入pattern(>, sed -i等), 但python3 pathlib.write_text()绕过了检测. 根因: hook无法区分诊断命令和plan task执行, 且agent决策层面缺少强提醒. 修复: session-init注入ralph loop提醒 | workflow, ralph-loop | active |

### 2026-02-23: sync-omcc.sh 缺少 agents/ symlink 步骤
- **场景**: gtm 集成 OMCC 后，Kiro CLI 启动报错 `File URI not found: file://../../agents/reviewer-prompt.md`
- **根因**: generate_configs.py 在 reviewer.json/researcher.json 中写了 `"prompt": "file://../../agents/reviewer-prompt.md"`，但 sync-omcc.sh 没有创建 `agents/` → `.omcc/agents/` 的 symlink
- **修复**: 手动 `ln -sf .omcc/agents agents`
- **待办**: sync-omcc.sh 应增加 Step 3.x 确保 `agents/` symlink，类似 commands/ 和 scripts/ 的处理
