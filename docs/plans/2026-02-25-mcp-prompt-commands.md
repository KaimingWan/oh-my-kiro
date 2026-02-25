# MCP Prompt Commands — `@o/agent` & `@o/know`

**Goal:** Replace file-based custom commands with MCP prompts (Kiro) and CC skills (Claude Code) to enable parameter passing. Two commands: `agent` (沉淀顶层纲领 → `knowledge/rules.md`) and `know` (沉淀知识 → `knowledge/episodes.md`).

**Non-Goals:** Changing the knowledge distillation pipeline (distill.sh, auto-capture). Modifying AGENTS.md directly. Adding new knowledge categories beyond rules/episodes.

**Architecture:** Dual-platform implementation: (1) Kiro — lightweight MCP prompt server (`scripts/mcp-prompts.py`) registered in `.kiro/settings/mcp.json`, server name `o`, exposes `agent` and `know` prompts with optional `content` argument. (2) Claude Code — `.claude/skills/{agent,know}/SKILL.md` files using `$ARGUMENTS` substitution. (3) Delete `commands/reflect.md` (replaced by `know`). (4) Update `generate_configs.py` to output CC skill files. (5) Update `sync-omcc.sh` to symlink skills.

**Tech Stack:** Python (MCP server via `mcp` SDK), Markdown (CC skills), bash (sync)

## Tasks

### Task 1: CC Skills — `agent` and `know`

**Files:**
- Create: `.claude/skills/agent/SKILL.md`
- Create: `.claude/skills/know/SKILL.md`
- Delete: `commands/reflect.md`

**Step 1: Write CC skill for `agent`**

Create `.claude/skills/agent/SKILL.md`:
```markdown
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
```

**Step 2: Write CC skill for `know`**

Create `.claude/skills/know/SKILL.md`:
```markdown
---
name: know
description: "Capture knowledge into episodes.md. Use when preserving insights, lessons learned, or corrections from the current conversation."
argument-hint: "[insight to capture]"
disable-model-invocation: true
---

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
```

**Step 3: Delete `commands/reflect.md`**

Remove the old file — its functionality is now in `know`.

**Step 4: Verify**

**Verify:** `test -f .claude/skills/agent/SKILL.md && test -f .claude/skills/know/SKILL.md && ! test -f commands/reflect.md && echo PASS`

### Task 2: MCP Prompt Server for Kiro

**Files:**
- Create: `scripts/mcp-prompts.py`

**Step 1: Write MCP prompt server**

Create `scripts/mcp-prompts.py` — a stdio MCP server exposing two prompts:

```python
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
```

**Step 2: Verify server starts**

**Verify:** `cd /Users/wanshao/project/oh-my-claude-code && python3 -c "import mcp.server.fastmcp; print('OK')" 2>/dev/null && echo PASS || echo "NEED: pip install mcp"`

### Task 3: Register MCP Server in Kiro Config

**Files:**
- Modify: `.kiro/settings/mcp.json`

**Step 1: Add `o` server to mcp.json**

Add the `o` MCP server entry pointing to `scripts/mcp-prompts.py`:

```json
{
  "mcpServers": {
    "ripgrep": {
      "command": "npx",
      "args": ["-y", "mcp-ripgrep@latest"]
    },
    "o": {
      "command": "python3",
      "args": ["scripts/mcp-prompts.py"]
    }
  }
}
```

**Step 2: Verify**

**Verify:** `jq -e '.mcpServers.o.command' .kiro/settings/mcp.json | grep -q python3 && echo PASS`

### Task 4: Update generate_configs.py — CC Skill Generation

**Files:**
- Modify: `scripts/generate_configs.py`

**Step 1: Add CC skill generation to main()**

Add skill file generation after the CC agent markdown files section. Read skill content from the OMCC repo's `.claude/skills/` and write to the project's `.claude/skills/`.

Add to `main()` after the `for path, content in cc_targets:` loop (around line 310), before the final error check:

```python
    # CC skill files (commands with $ARGUMENTS support)
    skills_src = SCRIPT_ROOT / ".claude" / "skills"
    if skills_src.is_dir():
        skills_dst = PROJECT_ROOT / ".claude" / "skills"
        for skill_dir in skills_src.iterdir():
            if skill_dir.is_dir() and (skill_dir / "SKILL.md").exists():
                dst = skills_dst / skill_dir.name / "SKILL.md"
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_text((skill_dir / "SKILL.md").read_text())
                print(f"  ✅ {dst.relative_to(PROJECT_ROOT)}")
```

**Step 2: Verify**

**Verify:** `grep -q "CC skill files" scripts/generate_configs.py && echo PASS`

### Task 5: Update sync-omcc.sh — MCP Config Sync

**Files:**
- Modify: `tools/sync-omcc.sh`

**Step 1: Add mcp.json merge step**

After the existing mcp.json sync step (Step 3.9), ensure the `o` server entry is present. The sync script should merge the OMCC mcp.json into the project's mcp.json rather than overwrite (project may have its own MCP servers).

Find the existing Step 3.9 and update to merge the `o` server:

```bash
# ─── Step 3.9b: Ensure 'o' MCP prompt server is registered ───────────────────
MCP_JSON="$PROJECT_ROOT/.kiro/settings/mcp.json"
if command -v jq &>/dev/null; then
  mkdir -p "$(dirname "$MCP_JSON")"
  if [ ! -f "$MCP_JSON" ]; then
    echo '{"mcpServers":{"o":{"command":"python3","args":["scripts/mcp-prompts.py"]}}}' | jq . > "$MCP_JSON"
    ok "Step 3.9b: Created mcp.json with 'o' MCP server"
  elif ! jq -e '.mcpServers.o' "$MCP_JSON" &>/dev/null; then
    jq '.mcpServers.o = {"command": "python3", "args": ["scripts/mcp-prompts.py"]}' "$MCP_JSON" > "${MCP_JSON}.tmp" && mv "${MCP_JSON}.tmp" "$MCP_JSON"
    ok "Step 3.9b: 'o' MCP server registered in mcp.json"
  else
    info "Step 3.9b: 'o' MCP server already in mcp.json"
  fi
fi
```

**Step 2: Verify**

**Verify:** `grep -q "mcp-prompts" tools/sync-omcc.sh && echo PASS`

### Task 6: Update AGENTS.md Skill Routing Table

**Files:**
- Modify: `AGENTS.md`

**Step 1: Update skill routing table**

Add the two new commands to the Skill Routing table and remove the `@reflect` reference:

Add rows:
```
| 沉淀纲领 | agent (CC skill / MCP prompt) | `/agent` or `@o/agent` | 按需读取 |
| 沉淀知识 | know (CC skill / MCP prompt) | `/know` or `@o/know` | 按需读取 |
```

**Step 2: Verify**

**Step 1a: Remove @reflect row from Skill Routing table**

Replace the row `| 纠正/学习 | self-reflect | context-enrichment 检测 | 按需读取 |` — keep it but also add the two new rows right after it.

**Step 1b: Add new rows to Skill Routing table**

Insert after the self-reflect row:
```
| 沉淀纲领 | agent (CC skill / MCP prompt) | `/agent` or `@o/agent` | 按需读取 |
| 沉淀知识 | know (CC skill / MCP prompt) | `/know` or `@o/know` | 按需读取 |
```

**Verify:** `grep -q '@o/agent' AGENTS.md && grep -q '@o/know' AGENTS.md && echo PASS`

## Review

Round 1: All 4 reviewers REQUEST CHANGES. Issues found:
1. MCP server .format() injection risk → FIXED: use .replace()
2. Regression test tail pipe swallows exit code → FIXED: use `; test $? -eq 0`
3. Task 5 jq missing file handling → FIXED: creates mcp.json if missing
4. Task 4 insertion point vague → FIXED: specified line 310
5. Task 6 AGENTS.md update vague → FIXED: specified exact rows

Round 2: Goal Alignment APPROVE + Verify Correctness APPROVE.

**Verdict: APPROVE**

## Checklist

- [x] CC skill `agent` 存在且包含 $ARGUMENTS | `test -f .claude/skills/agent/SKILL.md && grep -q 'ARGUMENTS' .claude/skills/agent/SKILL.md && echo PASS`
- [x] CC skill `know` 存在且包含 $ARGUMENTS | `test -f .claude/skills/know/SKILL.md && grep -q 'ARGUMENTS' .claude/skills/know/SKILL.md && echo PASS`
- [x] `commands/reflect.md` 已删除 | `! test -f commands/reflect.md && echo PASS`
- [x] MCP server 脚本存在 | `test -f scripts/mcp-prompts.py && python3 -c "import ast; ast.parse(open('scripts/mcp-prompts.py').read())" && echo PASS`
- [x] mcp.json 包含 o server | `jq -e '.mcpServers.o.command' .kiro/settings/mcp.json | grep -q python3 && echo PASS`
- [ ] generate_configs.py 包含 skill 生成 | `grep -q "CC skill files" scripts/generate_configs.py && echo PASS`
- [ ] sync-omcc.sh 包含 MCP 注册 | `grep -q "mcp-prompts" tools/sync-omcc.sh && echo PASS`
- [ ] AGENTS.md 包含新命令 | `grep -q '@o/agent' AGENTS.md && grep -q '@o/know' AGENTS.md && echo PASS`
- [ ] 回归测试通过 | `python3 -m pytest tests/ -v --timeout=30; test $? -eq 0 && echo PASS`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## Findings
