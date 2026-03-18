---
name: omk-know
description: "Capture knowledge into episodes.md. Trigger when user says 'remember', 'capture this', 'lesson learned', 'note this', '@know', or when preserving insights, corrections, or discoveries from the current conversation."
argument-hint: "[insight to capture]"
disable-model-invocation: true
---

## Trigger Examples
- "@know macOS stat 用 -f 不用 -c"
- "记一下这个坑"
- "capture this lesson"
- "note: this API requires auth header"
- "@know HubSpot API 有 rate limit 100/10s"

# Know — Knowledge Capture

Read the current conversation and capture an insight into knowledge/episodes.md.

## Input
$ARGUMENTS

## Process
1. If no input provided, ask user: "What insight should I capture?"
2. Extract: trigger scenario + DO/DON'T action + keywords
3. Check dedup: grep -iw keywords in knowledge/rules.md and knowledge/episodes.md
   - Already in rules → tell user, skip
   - Already in episodes → tell user count, suggest promotion if ≥3
4. Format: `DATE | active | KEYWORDS | SUMMARY` (≤80 chars, no | in summary)
5. Append to knowledge/episodes.md
6. Output: 📝 Captured → episodes.md: 'SUMMARY'

## Rules
- Summary must contain actionable DO/DON'T, not narrative
- Keywords: 1-3 english technical terms, ≥4 chars each, comma-separated
- If episodes.md has ≥30 entries, warn user to clean up first
