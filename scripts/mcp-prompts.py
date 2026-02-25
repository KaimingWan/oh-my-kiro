#!/usr/bin/env python3
"""MCP Prompt Server for OMCC — exposes agent/know prompts with optional arguments."""
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("o")

AGENT_PROMPT = """\
# Agent — Distill Top-Level Principle

Capture a principle into knowledge/rules.md as a staged rule.

## Input
{content}

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
"""

KNOW_PROMPT = """\
# Know — Knowledge Capture

Read the current conversation and capture an insight into knowledge/episodes.md.

## Input
{content}

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
"""


@mcp.prompt()
def agent(content: str = "") -> str:
    """Distill a top-level principle into knowledge/rules.md."""
    return AGENT_PROMPT.replace("{content}", content or "(no input — ask user)")


@mcp.prompt()
def know(content: str = "") -> str:
    """Capture knowledge into knowledge/episodes.md."""
    return KNOW_PROMPT.replace("{content}", content or "(no input — ask user)")


if __name__ == "__main__":
    mcp.run(transport="stdio")
