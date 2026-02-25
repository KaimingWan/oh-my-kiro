---
name: agent
description: "Distill a top-level principle into knowledge/rules.md. Use when capturing architectural decisions, workflow principles, or behavioral guidelines."
argument-hint: "[principle to capture]"
disable-model-invocation: true
---

# Agent — Distill Top-Level Principle

Capture a principle into knowledge/rules.md as a staged rule.

## Input
$ARGUMENTS

## Process
1. If no input provided, ask user: "What principle should I capture?"
2. Extract: trigger scenario + DO/DON'T action + keywords
3. Check dedup: grep -iw keywords in knowledge/rules.md and knowledge/episodes.md
   - Already in rules → tell user, skip
   - Already in episodes with same meaning → tell user, suggest upgrading to rule
4. Determine severity: 🔴 (critical, always inject) or 🟡 (relevant, keyword-matched)
5. Find or create matching section header `## [keyword1,keyword2]` in knowledge/rules.md
6. Append rule under that section, format: `🔴 N. SUMMARY` or `🟡 N. SUMMARY`
7. Cap: max 5 rules per section, max 30 rules total. Warn if approaching limit.
8. Output: 📝 Captured → rules.md: 'SUMMARY'

## Rules
- Summary must contain actionable DO/DON'T, not narrative
- Keywords: 1-3 english technical terms, ≥4 chars each, comma-separated
- Default severity: 🟡 (only use 🔴 for principles that should apply to EVERY conversation)
