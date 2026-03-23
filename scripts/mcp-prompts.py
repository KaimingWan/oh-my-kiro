#!/usr/bin/env python3
"""MCP Prompt Server for OMK — exposes agent/know prompts with optional arguments."""
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


CK_PROMPT = """\
# CK — Checkout Branch into Worktree

Checkout a branch in a submodule and create a worktree for development.

## Input
{content}

## Process
1. If no branch name provided, list recent remote branches and ask user to pick:
   ```bash
   git fetch origin --prune --quiet
   git branch -r --sort=-committerdate | head -15
   ```
2. Fuzzy search: match input against local and remote branches
   ```bash
   git branch --list "*QUERY*" --sort=-committerdate | head -10
   git branch -r --list "*QUERY*" --sort=-committerdate | head -10
   ```
3. If multiple matches, show numbered list and ask user to pick
4. If exactly one match, confirm with user
5. Determine submodule from current directory or ask user
6. Create worktree:
   ```bash
   branch="<selected>"
   sm_name=$(basename $(pwd))
   slug=$(echo $branch | sed 's#origin/##; s#/#-#g')
   git worktree add "../../worktrees/${{sm_name}}-${{slug}}" -b "$(echo $branch | sed 's#origin/##')" "$branch" 2>/dev/null \\
     || git worktree add "../../worktrees/${{sm_name}}-${{slug}}" "$branch"
   ```
7. Write .active-submodule:
   ```bash
   jq -n --arg sm "$sm_name" --arg wt "worktrees/${{sm_name}}-${{slug}}" '{{submodule:$sm,worktree:$wt}}' > ../../.active-submodule
   ```
8. Report: worktree path, branch name, remind to run `code init`
"""


PLAN_PROMPT = """\
You MUST follow this exact sequence. Do NOT skip or reorder any step.

## Step 1: Deep Understanding (skill: planning Phase 0)
Follow skills/omk-planning/SKILL.md Phase 0 to build deep understanding of the goal. Ask clarifying questions, research if needed, and present design for creative/architectural work. Do NOT proceed until the user confirms the direction. After user confirms: `touch .brainstorm-confirmed`

## Step 2: Writing Plan (skill: planning)
Read skills/omk-planning/SKILL.md, then write a plan to docs/plans/<date>-<slug>.md. The plan MUST include: Goal, Steps with TDD structure, an empty ## Review section, and a ## Checklist section with all acceptance criteria as `- [ ]` items. The checklist is the contract — @execute will not proceed without it.

### Checklist Structure Rules (CRITICAL — Ralph Loop depends on these)
1. **All checklist items go in the `## Checklist` section** (as defined in SKILL.md). Do NOT scatter `- [ ]` items inline across Phases — Ralph Loop and hooks parse `## Checklist` as the single source of truth.
2. **Each checklist item MUST include an inline verify command** using the format: `- [ ] Description | \\`verify_command\\`` (e.g., `- [ ] Gateway responds 200 | \\`curl -sf http://127.0.0.1:8000/health\\``). The verify command must return exit code 0 on success.
3. **Checklist items must be actionable, not just observational.** Bad: `- [ ] System looks good`. Good: `- [ ] Config validated | \\`python3 -c "import json; json.load(open('config.json'))"\\``.
4. **NEVER mark `- [x]` without running the verify command.** Ralph Loop's `revert_failed_checks()` will revert items whose verify commands fail.

## Step 3: Verify Checklist Exists
Before dispatching reviewer, confirm the plan file contains a `## Checklist` section with at least one `- [ ]` item. If missing, add it NOW — do not proceed to review without it.

## Step 4: Plan Review (skill: planning)
Follow `skills/omk-planning/SKILL.md` Phase 1.5 for plan review. Select review angles based on plan complexity, dispatch reviewer subagent(s), and apply calibration rules defined there.

## Step 5: Address Feedback
If reviewer verdict is REQUEST CHANGES or REJECT:
  - Fix the plan based on reviewer feedback
  - Mark old decisions as ~~deprecated~~ with reason
  - Re-dispatch reviewer for a second round
  - Repeat until APPROVE

## Step 6: User Confirmation
Show the final plan with reviewer verdict. User confirms by saying `@execute` (which also triggers execution) or just "确认"/"confirm".

## Step 7: Hand Off to Execute
After user confirms (including via `@execute`):
1. Write the plan file path to `docs/plans/.active` (e.g., `echo "docs/plans/2026-02-14-feature-x.md" > docs/plans/.active`)
2. Clean up: `unlink .brainstorm-confirmed 2>/dev/null || true`
3. **Auto-commit plan artifacts** — ralph_loop.py requires a clean working tree. Only commit files the agent created/modified during this plan session (plan file, .active, any skill/prompt changes). Do NOT `git add -A` — user may have unrelated edits in progress. Use explicit file paths:
   ```
   git add docs/plans/<plan-file>.md docs/plans/.active [other files agent touched]
   git commit -m "plan: <plan-slug> (reviewed, approved)"
   ```
   If `git status --porcelain` still shows untracked/modified files after this commit, warn the user: "You have uncommitted changes outside this plan. Stash or commit them before @execute."
4. Launch Ralph Loop:
   ```bash
   python3 scripts/ralph_loop.py
   ```
   Report results when it finishes (see commands/execute.md Step 4).

---
User's requirement:
{content}
"""

DO_PROMPT = """\
Lightweight command for small tasks (< 1 hour). No plan file, no review dispatch.

## Task
{content}

## Stage 1: Scratchpad (MANDATORY)

Before ANY code change, write a scratchpad to `/tmp/task-scratch.md`:

```markdown
## Task: <one-line description>
- Files: <list files to read/modify, discovered via LSP>
- Constraint: <key constraints or gotchas>
- Verify: <how to verify success>
```

Discovery steps (silent, no user output):
1. `search_symbols` / `find_references` / `get_diagnostics` to identify all affected files
2. Read each affected file's relevant sections (NOT entire files — use line offsets)
3. Update scratchpad with actual file list and key findings

## Stage 2: Execute

Make changes following `skills/omk-coding/SKILL.md` Phase 1-4.

**Context anchor rule**: After EVERY code modification, append a one-line status to the scratchpad:
```
- [done] modified file L37-41: description
- [blocked] test fails: reason
```

## Stage 3: Verify

1. Run the verify method from scratchpad
2. Re-read scratchpad to confirm all items addressed
3. Report result to user

## Multi-turn recovery

If the conversation has gone ≥ 3 turns on this task:
1. STOP and re-read `/tmp/task-scratch.md`
2. Compare current state vs scratchpad — identify drift
3. If drifted, state what drifted and correct course
"""

DEBUG_PROMPT = """\
You MUST follow this exact sequence. @debug is a fully automated debugging pipeline — no user confirmation between stages. The goal is systematic root cause analysis, not guess-and-check.

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

## Bug Report
{content}

## Stage 1: Triage & Context

1. Read `knowledge/episodes.md` — check if this bug pattern has occurred before
2. Build Architectural Context around the bug:
   - `find_references` on bug's core symbol(s) → all callers
   - `get_document_symbols` on bug's file(s) → internal structure
3. Classify failure type (Logic/Semantic | Environment/Config | Concurrency/Timing | Invalid Invocation | Under-specified Intent)
4. Write triage summary to `/tmp/debug-scratch.md`

## Stage 2: Root Cause Investigation

Follow `skills/omk-debugging/SKILL.md` Phase 1 + `references/root-cause-protocol.md`. Use LSP tools, NOT grep:

1. `get_diagnostics` on failing file(s)
2. `search_symbols` → `goto_definition` → `find_references` on involved symbols
3. Read error messages / stack traces completely
4. Reproduce the bug consistently
5. Check recent changes (`git diff`, recent commits)

Produce **Diagnostic Evidence** before proceeding. **Gate:** Without Diagnostic Evidence, DO NOT proceed to Stage 3.

## Stage 3: Pattern Analysis & Hypothesis

Follow `skills/omk-debugging/SKILL.md` Phase 2-3 + `references/pattern-analysis.md`.

1. Find working examples → compare working vs broken → list ALL differences
2. Form ONE hypothesis: "X is the root cause because Y"
3. Test with the SMALLEST possible change — one variable at a time
4. If hypothesis fails → form NEW hypothesis, don't stack fixes

**Gate:** Hypothesis must be confirmed before proceeding to Stage 4.

## Stage 4: Fix & Verify

Follow `skills/omk-debugging/SKILL.md` Phase 4 + `references/implementation-fix.md`.

1. `get_diagnostics` → record baseline
2. Create failing test case (if possible)
3. Implement SINGLE fix addressing root cause — no bundled changes
4. `get_diagnostics` → zero new diagnostics, or revert
5. Run tests → verify fix, no regressions
6. Self-explain: root cause → fix logic → side effects

**3-Strike Rule:** If 3 fix attempts fail → STOP, question the architecture, discuss with user.

## Stage 5: Report

```markdown
## Debug Report
- **Bug:** <description>
- **Root Cause:** <what was actually wrong>
- **Fix:** <what was changed and why>
- **Verification:** <test results>
- **Side Effects:** <none | list>
```

If bug is a new pattern, append one-line summary to `knowledge/episodes.md`.

## Red Flags — Auto-Rollback to Stage 2

Proposing fixes without evidence / using grep instead of LSP / saying "just try X" / stacking changes / skipping reproduction → **STOP. Return to Stage 2.**
"""

AUTO_PROMPT = """\
You MUST follow this exact sequence. @auto is a fully automated pipeline — no user confirmation between stages except when Stage 1 determines a user decision is required.

## Stage 1: Autonomous Understanding（自主理解）

@auto 的核心区别于 @plan：自己搞清楚，不问用户。按以下步骤自主完成需求理解。

### 1.1 自建理解
- 读 knowledge/ 相关文件（通过语义搜索或目录浏览）
- 读相关代码/配置（如果任务涉及代码修改）
- 查 episodes.md 看有没有相关历史踩坑
- 形成初步理解：目标、现状、差距

### 1.2 自主调研
判断是否需要调研（这是你的判断，不是每次都需要）：
- 涉及不熟悉的外部工具/API/库 → web_search
- 涉及现有代码但没读过 → 读代码
- 涉及竞品/市场信息 → web_search + knowledge/competitive/
- 已经足够清楚 → 跳过

调研时同时覆盖理论基础和工程实践，避免空中楼阁或盲目照搬。

### 1.3 需求自扩展
基于 1.1 和 1.2 的结果，自己把模糊需求细化为具体 spec：
- 目标：一句话无歧义
- 约束：边界和非目标
- 交付物：具体输出形式
- 成功标准：至少 2 个可测试的验收条件
- 技术方案：基于调研的推荐方案

### 1.4 Readiness Check（自检）
用 4 维度自检（Goal / Constraints / Success Criteria / Context）：
- 所有维度 ✅ → 生成 spec 摘要，`touch .brainstorm-confirmed`，直接进 Stage 2
- 有维度 ❌ 但可以通过进一步调研解决 → 回到 1.2 补充调研（最多 1 次）
- 有维度 ❌ 且必须用户决策（如：选 A 方案还是 B 方案）→ 问用户，最多问用户 2 个问题，每个问题带推荐答案

### 关键原则
- 能自己搞清楚的绝不问用户
- 调研结果写入 spec，不丢弃
- 最多问用户 2 个问题（只问必须用户决策的）
- 超过 2 个不确定点 → 声明假设并继续

## Stage 2: Planning (Phase 1)

Phase 0 已在 Stage 1 完成，直接从 Phase 1（写 plan）开始。Read `skills/omk-planning/SKILL.md` Phase 1 section only — do NOT re-run Phase 0 steps. Write plan to `docs/plans/<date>-<slug>.md` with Goal, Tasks (TDD structure), `## Review`, and `## Checklist` with verify commands.

Follow all Checklist Structure Rules from the @plan prompt Step 2.

## Stage 3: Review (Phase 1.5 + Pre-mortem)

Follow `skills/omk-planning/SKILL.md` Phase 1.5:
1. Run **Pre-mortem Analysis** — identify 3 failure risks (Integration / Assumption / Environment)
2. Select review angles (2 fixed + 2 random = 4 reviewers)
3. Dispatch 4 reviewer subagents in parallel with pre-mortem questions injected

**Handling REQUEST CHANGES:**
- @auto autonomously revises the plan based on reviewer feedback (max 2 revision rounds)
- After each revision, re-dispatch reviewers for the changed sections
- If still REQUEST CHANGES after 2 rounds: **STOP** and tell the user what remains unresolved. User must intervene manually.

## Stage 4: Execution

After all reviewers APPROVE (or after user resolves remaining issues):
1. Write plan path to `docs/plans/.active`
2. `unlink .brainstorm-confirmed 2>/dev/null || true`
3. Auto-commit plan artifacts (explicit file paths only, never `git add -A`)
4. Launch Ralph Loop: `python3 scripts/ralph_loop.py`

## Stage 5: Completion

When Ralph Loop finishes:
- Report final status (completed / remaining / skipped items)
- If items remain, summarize what failed and suggest next steps
- Clean up `.active` if all items completed

---
User's requirement:
{content}
"""

REVIEW_PROMPT = """\
# @review — Code Review

Dispatch a code review following `skills/omk-reviewing/SKILL.md`.

## Scope
{content}

## Steps

### 1) Determine diff range
- If user provided a diff range (e.g., `main..HEAD`), use it
- If user said "review this PR" or similar, detect: `git merge-base main HEAD`..`HEAD`
- If no range specified, review all uncommitted + staged changes: `git diff HEAD`
- Run `git diff --stat <range>` to understand scope

### 2) Dispatch reviewer subagent

Dispatch **1 reviewer subagent** (`agent_name: "reviewer"`) with this query:

```
Review the code changes in range <RANGE>.

You MUST read and follow these reference checklists:
- skills/omk-reviewing/references/solid-checklist.md
- skills/omk-reviewing/references/security-checklist.md
- skills/omk-reviewing/references/code-quality-checklist.md
- skills/omk-reviewing/references/removal-plan.md
- skills/omk-reviewing/references/output-format.md

Execute the 7-step review process from skills/omk-reviewing/SKILL.md "Executing Code Review" section:
1) Preflight: git diff --stat then git diff. If >500 lines, batch by module.
2) SOLID + architecture check (load solid-checklist.md)
3) Security scan (load security-checklist.md)
4) Code quality scan (load code-quality-checklist.md)
5) Removal candidates (load removal-plan.md)
6) Output findings using output-format.md (P0/P1/P2/P3)
7) Present next steps — do NOT implement changes until user confirms
```

### 3) Report findings
Present the reviewer's findings to the user. Follow the "Receiving Review" section of the skill for handling feedback.
"""

CPR_PROMPT = """\
Commit all changes, push to remote, and create a Pull Request. (CPR = Commit Push PR)

## Scope
Only operate on the current git repository. NEVER cd into or commit/push other repositories.

## Steps

### Step 1: Stage & Commit
1. `git add -A && git status --short` — show what's staged
2. Ask user for commit message if not provided, or generate one from the diff
3. `git commit -m "<message>"`
4. `git push`
5. Report: commit hash + push result

### Step 2: Detect PR Target Branch

```bash
current_branch=$(git branch --show-current)

# 1. Check reflog for source branch (works for worktree branches)
created_from=$(git reflog show "$current_branch" --format="%gs" | tail -1 | sed 's/.*Created from //')
base=$(echo "$created_from" | sed 's#refs/remotes/origin/##; s#refs/heads/##')

# 2. If source == self (created from remote tracking branch), fallback to remote default
if [ "$base" = "$current_branch" ] || [ -z "$base" ]; then
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
  [ -z "$base" ] && base="main"
fi

echo "PR_TARGET=$base"
```

Show the detected target branch to user and ask for confirmation:
- "PR target: `<base>`. Confirm? (or specify a different branch)"
- If user provides a different branch, use that instead.

User override for target branch: {content}

### Step 3: Create PR

```bash
gh pr create --base "$base" --title "<generate from commits>" --body "<summary of changes>"
```

Report: "PR created: <url>. Target: `<base>`."

### Step 4: Worktree Cleanup (only if in worktree)

```bash
wt_dir=$(git rev-parse --git-common-dir 2>/dev/null)
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [ "$wt_dir" != "$git_dir" ]; then
  worktree_path=$(pwd)
  cd "$(git worktree list | head -1 | awk '{print $1}')"
  git worktree remove "$worktree_path" --force
  echo "Worktree cleaned up."
fi
```

## Edge Cases
- **No gh CLI:** Warn user, skip PR creation. Just commit + push.
- **No changes to commit:** Skip commit, still create PR if there are pushed commits not yet in a PR.
- **User on main/default branch:** Warn "You're on the default branch, PR doesn't make sense." and abort.
"""

RESEARCH_PROMPT = """\
You MUST read skills/omk-research/SKILL.md first, then follow its search level strategy.

## Rules
1. Start at Level 0 (built-in knowledge). Only escalate if insufficient.
2. Level 1: use web_search for quick verification.
3. Level 2: use deep research API only for comprehensive research.
4. Write all findings to a file (knowledge/ or docs/research/) — do NOT leave research only in chat.
5. Cite sources for any factual claims.

## Research topic:
{content}
"""

@mcp.prompt()
def plan(content: str = "") -> str:
    """Create an implementation plan. Pass your requirement as the argument."""
    return PLAN_PROMPT.replace("{content}", content or "(no requirement provided — ask the user)")


@mcp.prompt()
def auto(content: str = "") -> str:
    """Fully automated pipeline: plan → review → execute. Pass your requirement as the argument."""
    return AUTO_PROMPT.replace("{content}", content or "(no requirement provided — wait for user's next message)")


@mcp.prompt()
def debug(content: str = "") -> str:
    """Systematic debugging pipeline: triage → root cause → hypothesis → fix → report. Pass bug description."""
    return DEBUG_PROMPT.replace("{content}", content or "(no bug report provided — wait for user's next message)")


@mcp.prompt()
def cpr(content: str = "") -> str:
    """Commit, push, and create a PR. Optionally pass target branch override."""
    return CPR_PROMPT.replace("{content}", content or "(no override — auto-detect target branch)")


@mcp.prompt()
def research(content: str = "") -> str:
    """Research a topic using L0→L1→L2 strategy. Pass the research topic."""
    return RESEARCH_PROMPT.replace("{content}", content or "(no topic provided — ask the user)")


@mcp.prompt()
def ck(content: str = "") -> str:
    """Checkout a branch into a submodule worktree. Pass branch name or keyword to fuzzy search."""
    return CK_PROMPT.replace("{content}", content or "(no branch specified — list recent branches)")


@mcp.prompt()
def review(content: str = "") -> str:
    """Code review with SOLID, security, quality, and removal checks. Pass diff range or description."""
    return REVIEW_PROMPT.replace("{content}", content or "(no scope specified — review all uncommitted changes)")


@mcp.prompt()
def do(content: str = "") -> str:
    """Lightweight task execution (< 1 hour). Pass your task description."""
    return DO_PROMPT.replace("{content}", content or "(no task provided — wait for user's next message)")


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
