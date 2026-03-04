<!-- BEGIN OMCC WORKFLOW -->
## Workflow
- Explore → Plan → Code（先调研，再计划，再编码）
- 复杂任务先 interview，不要假设
- **涉及多文件改动的任务，必须读取 `skills/planning/SKILL.md` 并严格执行完整流程：**
  1. Phase 0: Deep Understanding（调研 + 提问）
  2. Phase 1: Write Plan（写到 `docs/plans/`，必须有 `## Tasks` + `## Checklist` + `## Review`）
  3. Phase 1.5: Plan Review（dispatch 4 个 reviewer subagent 并行 review）
  4. Phase 2: Execute（用户确认后通过 ralph loop 执行）
  5. **禁止跳过 Phase 1.5 的 reviewer dispatch，禁止自己 review 自己的 plan**

## Skill Routing

| 场景 | Skill | 触发方式 | 加载方式 |
|------|-------|---------|---------|
| 规划/设计 | planning | `@plan` 命令 | 预加载 |
| 执行计划 | planning + ralph loop | `@execute` 命令 | 预加载 |
| Code Review | reviewing | `@review` 命令 | 预加载 |
| 调试 | debugging | rules.md 自动注入 | 按需读取 |
| 调研 | research | `@research` 命令 | 按需读取 |
| 完成前验证 | verification | Stop hook 自动 | 按需读取 |
| 分支收尾 | finishing | planning 完成后 | 按需读取 |
| 纠正/学习 | self-reflect | context-enrichment 检测 | 按需读取 |
| 发现 skill | find-skills | 用户询问时 | 按需读取 |

## Knowledge Retrieval
- Question → knowledge/INDEX.md → topic indexes → source docs
- Hook 🔎 结果优先 — 有 OV 召回时先用召回内容，不够再 find/grep 补搜。禁止绕过 OV 直接搜文件系统
<!-- END OMCC WORKFLOW -->
