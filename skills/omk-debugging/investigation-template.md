# Investigation: {title}

> Created: {date} | Status: 🔴 Investigating / 🟡 Partial / 🟢 Resolved

## Problem Statement
<!-- 一句话描述问题，不超过 3 行 -->

## Status Overview
<!-- ⚡ 覆盖更新区域 — 每次有实质进展就刷新 -->

**状态**: 🔴 排查中
**根因确认度**: ⬜ 未确认

| # | 子问题 | 状态 | 根因 | 修复 |
|---|--------|------|------|------|
| 1 | {子问题描述} | ⬜ 未排查 | — | — |

**Investigation Tree:**
```
{问题}
├── {排查方向 1} → ⬜
└── {排查方向 2} → ⬜
```

**下一步**: {具体行动}
**阻塞项**: 无

## Evidence Table

### 🔒 L0 — Machine Facts (不可推翻)
<!-- 命令输出、代码分析、API 响应、实验结果 -->
<!-- APPEND-ONLY: 只增不删不改 -->

| # | 时间 | 证据 | 来源 | 关联 |
|---|------|------|------|------|
| F1 | {time} | {fact} | {command/code/api} | {相关子问题} |

### 👤 L1 — Human Observations (需充分理由才能质疑)
<!-- 用户报告的操作和现象 -->
<!-- APPEND-ONLY -->

| # | 时间 | 观察 | 报告人 | 置信度 |
|---|------|------|--------|--------|
| H1 | {time} | {observation} | {who} | 高/中/低 |

### 🤖 L2 — Agent Inferences (可修正)
<!-- AI 的推导、假设、分析结论 -->
<!-- 可标注 ~~struck~~ 表示已推翻，但不删除原文 -->

| # | 时间 | 推导 | 依据 | 状态 |
|---|------|------|------|------|
| I1 | {time} | {inference} | 基于 F1, H1 | ✅ 有效 / ❌ 已推翻 |

## Decision Log
<!-- APPEND-ONLY: 记录方案演进，防止重走已否定路径 -->

| # | 时间 | 决策 | 理由 | 状态 |
|---|------|------|------|------|
| D1 | {time} | {decision} | {rationale} | ✅ 采纳 / ❌ 被 D{n} 取代 |

## Experiment Log
<!-- APPEND-ONLY: 结构化实验记录 -->

#### EXP-001: {实验名称}
- **时间**: {time}
- **环境**: {browser/OS/endpoint}
- **操作**: {具体命令或步骤}
- **预期**: {expected}
- **实际**: {actual}
- **证据级别**: 🔒 L0
- **结论**: {conclusion}
- **关联**: → F{n}, D{n}

## Ruled Out
<!-- APPEND-ONLY: 已排除的方向，防止新 session 重新排查 -->

| # | 方向 | 排除理由 | 依据 |
|---|------|---------|------|
| R1 | {direction} | {why ruled out} | EXP-{n} / F{n} |

## Timeline
<!-- APPEND-ONLY: 排查历程时间线 -->

### {date} {time} — {milestone}
{详细描述}
