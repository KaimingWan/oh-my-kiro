# Knowledge Index

> This index helps the agent quickly locate materials to answer questions.

## Routing Table

| Question Type | Jump To | Example |
|--------------|---------|---------|
| Shell/JSON/platform rules | `.claude/rules/shell.md` | "What's the rule for JSON?" |
| Workflow/plan/test rules | `.claude/rules/workflow.md` | "How should I commit?" |
| Subagent/MCP rules | `.claude/rules/subagent.md` | "Can subagent use grep?" |
| Debugging rules | `.claude/rules/debugging.md` | "How to fix a bug?" |
| Security rules | `.claude/rules/security.md` | "What's blocked?" |
| Git workflow | `.claude/rules/git-workflow.md` | "How to branch?" |
| Agent-learned rules (staging) | `knowledge/rules.md` | "Any new patterns?" |
| Past mistakes & wins | `knowledge/episodes.md` | "Have we seen this before?" |
| Framework design & architecture | `docs/designs/2026-02-13-framework-v2-upgrade.md` | "How does the hook system work?" |
| Hook architecture & governance | `docs/designs/2026-02-18-hook-architecture.md` | "Hook classification? New hook process?" |
| Reference materials (archived skills) | `knowledge/reference/` | "Mermaid syntax?" |

## Quick Links
- [Rules (staging)](rules.md) — Agent-discovered rules, candidates for promotion to `.claude/rules/`
- [Episodes](episodes.md) — Mistakes and wins (timeline)
- [Shell Rules](../.claude/rules/shell.md) — JSON, bash, platform compatibility
- [Workflow Rules](../.claude/rules/workflow.md) — Plans, reviews, testing, commits
- [Security Rules](../.claude/rules/security.md) — Hooks, injection, workspace boundaries
- [Framework v2 Design](../docs/designs/2026-02-13-framework-v2-upgrade.md) — Architecture & hooks
- [Hook Architecture](../docs/designs/2026-02-18-hook-architecture.md) — Hook governance, classification, lifecycle
- [Reference Materials](reference/) — Archived skill content (writing style, mermaid, java, etc.)

---
*Index version: 8.0 — Added Claude Code research doc*
