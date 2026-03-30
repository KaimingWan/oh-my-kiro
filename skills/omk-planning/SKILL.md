---
name: omk-planning
description: "Full plan lifecycle: deep understanding → write plan with TDD checklist → parallel review → Ralph Loop execution. Trigger when user says 'plan', 'design', 'implement', 'build', 'architect', '@plan', '@execute', or describes a multi-step task that needs structured breakdown. Also trigger for feature requests, system redesigns, or migration projects."
---

## Trigger Examples
- "@plan 重构 hook 系统"
- "I want to add OAuth support, help me plan it"
- "设计一个新的 knowledge 同步方案"
- "@execute 继续执行计划"
- "break this feature into tasks"

# Planning — Write, Review, Execute

## Overview

One skill for the full plan lifecycle: write → review → execute.

## Phase 0: Deep Understanding

Before writing any plan, build deep understanding of the goal. Skip this phase only if the user provides a fully specified design doc.

### Step 1: Form Initial Understanding

Start with `generate_codebase_overview` to get the project's high-level structure, then read relevant code, docs, and recent commits to understand the context. Do NOT ask questions yet — first build your own mental model of:
- What the user wants to achieve
- What exists today (current state)
- What would need to change (gap analysis)

### Step 2: Ask Clarifying Questions

Based on your understanding, ask questions **one at a time**. Each question must:
- Eliminate a whole branch of ambiguity (not trivial details)
- Build on previous answers (incremental deepening)
- Offer multiple-choice options with your recommendation when possible

**Dynamic termination:** Stop asking when remaining uncertainty won't materially affect the plan. Don't ask for the sake of asking.

**Soft cap:** Maximum 5 questions. If you still have uncertainty after 5, state your assumptions and proceed.

### Step 3: Research (optional)

After questions are answered, judge whether research is needed:
- **Codebase research:** When the task touches existing code you haven't fully explored (e.g., modifying a hook system — read existing hooks first)
- **Web research:** When the task involves external tools, APIs, or best practices you're unsure about (e.g., integrating a new library, adopting an unfamiliar pattern)
- **Both:** When the task combines internal changes with external dependencies (e.g., adding OAuth to an existing auth module)
- **Skip:** When you have sufficient understanding (e.g., renaming a variable, fixing a typo, simple refactors with clear scope)

**Research dimension principle:** When research IS needed, cover both theoretical foundations (papers, docs, design rationale) AND engineering practice (real implementations, battle-tested patterns, known pitfalls). One without the other leads to either ivory-tower designs or cargo-culted solutions.

This is your judgment call — not every plan needs research.

### Step 4: Supplementary Questions (if any)

After research, absorb what you learned. Only ask the user about findings you **cannot resolve from research alone** — things requiring user decisions or preferences.

If no supplementary questions needed, proceed directly to Phase 1.

### Step 5: Design presentation (optional)

When the task involves creative/architectural work (new features, new components, significant behavior changes), present the design before writing the plan:

- Break the design into sections of 200-300 words
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Write the validated design to `docs/designs/YYYY-MM-DD-<topic>-design.md`

Skip this step for simple refactors, bug fixes, or tasks with a fully specified design doc.

### Step 6: Readiness Check

Before proceeding to Phase 1, verify the task is well-defined across 4 dimensions:

| Dimension | ✅ Criterion | Greenfield | Brownfield |
|-----------|-------------|------------|------------|
| **Goal** | 能用一句话无歧义地说清楚要做什么 | Required | Required |
| **Constraints** | 边界、非目标、限制条件已明确 | Required | Required |
| **Success Criteria** | 至少有 2 个可测试的验收标准 | Required | Required |
| **Context** | 理解被修改的现有代码/系统 | Skip | Required |

Rules:
- All applicable dimensions must be ✅ to proceed to Phase 1
- If any dimension is ❌, ask ONE question targeting the weakest dimension
- This step adds at most 3 questions (on top of Step 2's questions)
- User says "skip" → state assumptions and continue

**Challenge Modes** (activate on 2nd+ question in this step):
- **Contrarian** (2nd question): "如果 [核心假设] 是错的呢？"
- **Simplifier** (3rd question): "最简版本是什么样的？"

### Transition to Phase 1

#### Goal-Backward Derivation

After the Readiness Check, reverse-engineer from Success Criteria before writing the plan:

For each Success Criterion:
1. **What must be TRUE** for this criterion to pass?
2. Which of these truths **already exist** in the codebase?
3. Which must be **newly created**? → These become Tasks
4. What are the **dependencies** between new truths? → These determine Task order

This ensures the plan covers everything needed for the goal, not just what seems obvious forward-thinking.

#### Socratic Self-Check

Then validate each major design decision:
1. **Essence** — What is the core problem this decision solves?
2. **Framework** — Does the current codebase already solve this? What known patterns apply?
3. **Application** — Is this feasible on all target platforms? Does benefit > maintenance cost?

Drop any decision that fails step 2 (already solved) or step 3 (infeasible/not worth it).

Then proceed to Phase 1 with the accumulated understanding.

### Error Handling

- **No relevant code/docs found:** Inform the user, ask them to point you to the right area, then continue.
- **User wants to skip Phase 0:** Allowed. User can say "skip questions" or "just write the plan" at any time. State your assumptions and proceed to Phase 1.
- **Contradictory answers:** Surface the contradiction to the user, ask them to clarify which direction to take.
- **5-question cap reached with critical ambiguity:** State remaining assumptions explicitly, proceed to Phase 1. The plan will note these assumptions for reviewer scrutiny.

## Phase 1: Writing the Plan

**Save to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

### Plan Header (required)

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Non-Goals:** [What this plan explicitly does NOT do]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]
**Work Dir:** [Relative path to working directory, e.g. `src/` or `.`]

## Review
<!-- Reviewer writes here -->
```

### Checklist Format (enforced by hook)

Every plan must have a `## Checklist` section. Every checklist item MUST include an executable verify command:

```markdown
- [ ] description | `verify command`
```

Examples:
- `- [ ] hook 语法正确 | \`bash -n hooks/security/my-hook.sh\``
- `- [ ] config 包含新 hook | \`jq '.hooks' .kiro/agents/pilot.json | grep -q my-hook\``
- `- [ ] 外部路径被拦截 | \`echo '{"tool_name":"fs_write","tool_input":{"file_path":"/tmp/evil.txt"}}' | bash hooks/security/my-hook.sh 2>&1; test $? -eq 2\``

Rules:
- verify command must be executable (no "手动测试", no "目视检查")
- verify command must return exit 0 on success
- Each Task must have at least 1 checklist item
- Cover: happy path + edge case + integration (where applicable)
- Hook enforces: checking off `- [x]` requires recent successful execution of the verify command
- **Regression test rule:** If plan Files fields include `scripts/ralph_loop.py` or `scripts/lib/`, the checklist MUST include: `- [ ] 回归测试通过 | \`python3 -m pytest tests/ralph-loop/ -v\``
- **Vertical slice rule:** Organize tasks as vertical slices (one feature end-to-end) rather than horizontal layers (all models, then all APIs). Vertical slices have fewer inter-task dependencies, enabling cleaner atomic commits. Exception: tasks that are inherently horizontal (e.g., "add logging to all hooks") need not be forced into vertical slices.

### Coarse Checklist Items

Checklist items can be high-level ("coarse") as long as the verify command is meaningful. The executing agent uses the Reasoning Loop (OBSERVE → THINK → PLAN → EXECUTE → REFLECT → CORRECT → VERIFY) to autonomously decompose coarse items into concrete sub-steps.

**Fine-grained vs coarse examples:**

| Style | Item | When to use |
|-------|------|-------------|
| Fine | `- [ ] Add timeout param to fetch() \| \`grep -q 'timeout' src/fetch.py\`` | Simple, single-change tasks |
| Coarse | `- [ ] Implement user auth module \| \`python3 -m pytest tests/auth/ -v\`` | Multi-step tasks where the agent decides implementation details |

**Rules for coarse items:**
- Verify command must still be executable and exit 0 — this is non-negotiable
- Prefer module-level or integration-level test commands as verify (e.g., `python3 -m pytest tests/module/ -v`)
- The Task body should describe the goal and constraints, not every line of code
- The executing agent will autonomously decompose using the Reasoning Loop

### Task Structure (TDD)

Each task follows red-green-refactor:

```markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write failing test**
[Complete test code]

**Step 2: Run test — verify it fails**
Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL

**Step 3: Write minimal implementation**
[Complete implementation code]

**Step 4: Run test — verify it passes**
Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**
```

Rules: exact file paths, complete code (not "add validation"), exact commands with expected output.

### Errors Section (required)

Every plan must have an `## Errors` section at the bottom. During execution, log every error encountered:

```markdown
## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|
```

Rules:
- Log immediately when error occurs, don't wait
- Include which Task triggered the error
- Track attempt number — if same error appears at attempt 3, trigger 3-Strike Protocol (see Phase 2)
- This section is append-only during execution — never delete entries
- Cap: keep most recent 20 entries; if exceeded, summarize older entries into a single "Earlier errors: N resolved" row

### Findings Section (optional)

Plans may include a `## Findings` section for persisting research discoveries made during execution:

```markdown
## Findings

- [discovery with context]
```

Rules:
- Append-only — never rewrite, only add new entries
- Use when execution-phase research reveals something relevant to later tasks
- Not required for simple plans where no research happens during execution

### Session State Section (optional)

Plans may include a `## Session State` section for cross-session continuity:

```markdown
## Session State

**Position:** Task N of M
**Last session:** YYYY-MM-DD HH:MM
**Decisions made this session:**
- [decision with rationale]

**Notes for next session:**
- [what to pick up, what to watch out for]
```

Rules:
- Updated at the end of each Ralph Loop round (before agent exits)
- Read at the start of each round (part of Session Resume Protocol)
- Append-only for decisions; position and notes are overwritten each round
- Not required for small plans (≤ 3 items) that complete in a single round

## Phase 1.5: Plan Review

After writing the plan, run multi-perspective plan review before execution.

### Angle Pool

Two categories: **fixed** (every round) and **random** (sampled each round).

**Fixed angles (always included):**

| Angle | Mission | Output |
|-------|---------|--------|
| Goal Alignment | You MUST copy each table below and fill EVERY cell. Do NOT summarize or skip rows. If a table has N tasks, your output must have N rows. Missing rows = review REJECTED. Copy and fill this table for EVERY task:\n\n\| Task # \| Goal phrase served (quote exact words) \| If removed, which Goal phrase loses coverage? \|\n\|--------\|---------------------------------------\|----------------------------------------------\|\n\| 1 \| [quote] \| [answer] \|\n\nThen copy and fill the coverage matrix:\n\n\| Goal phrase (copy from plan header) \| Covered by Task #s \|\n\|-------------------------------------\|-------------------\|\n\| [phrase 1] \| [list] \|\n\nFinally: trace the execution order — does Task N's output feed correctly into Task N+1's input? Findings must cite specific Task numbers and Goal phrases. | Missing Coverage / Unnecessary Tasks / Ordering Issues / Verdict |
| Verify Correctness | For each checklist verify command, you MUST copy this table and fill in EVERY cell:\n\n\| # \| Verify command \| Confirms what \| Exit code (correct impl) \| Exit code (broken impl) \| Sound? \|\n\|---\|---------------\|---------------\|--------------------------|--------------------------|--------\|\n\| 1 \| [copy from plan] \| [fill] \| [trace: ... → exit ?] \| [trace: ... → exit ?] \| [Y/N + reason] \|\n\nRules: EVERY row must show the shell execution trace, not just "exit 0". If you skip a row or write "all sound" without per-row traces, your review is REJECTED. Only flag commands where correct and broken give the SAME exit code. | False Positives / Weak Verifications / Verdict |

**Random pool (2 sampled per round):**

| Angle | Mission | Analysis Method | Output |
|-------|---------|-----------------|--------|
| **All angles** | Before writing any finding, verify it is within the plan's stated Goal and NOT in Non-Goals. Findings outside scope are noise — discard silently. | — | — |
| Completeness | You MUST copy each table below and fill EVERY cell. Missing rows = review REJECTED.\n\nFor each file in the plan's Files: fields that is MODIFIED (not created), copy and fill:\n\n\| File \| Function/Branch \| Exercised by Task # \| Coverage? \|\n\|------\|----------------\|--------------------\|-----------\|\n\| [path] \| [name] \| [task # or NONE] \| [Y/N] \|\n\nThen for each error path (try/except, if-error-return, signal handler) in modified files:\n\n\| File:line \| Error path \| Exercised by Task # \|\n\|----------\|------------|--------------------\|\n\| [path:line] \| [description] \| [task # or NONE] \|\n\nSCOPE: Only analyze functions/branches in files the plan MODIFIES. Do NOT flag functions in files the plan merely reads. | Source-to-task traceability matrix | Uncovered Functions / Unexercised Error Paths / Verdict |
| Testability | You MUST copy this table and fill EVERY cell. Missing rows = review REJECTED.\n\nFor each Task's test case:\n\n\| Task # \| Assertion (what property) \| Minimal wrong impl that passes \| False negative? \|\n\|--------\|--------------------------|-------------------------------|----------------\|\n\| [N] \| [what is checked] \| [describe wrong impl] \| [Y/N + reason] \|\n\nOnly flag tests where you can construct a concrete wrong implementation that passes. "Might be weak" without a specific wrong impl = not actionable. | False negative analysis per test | Weak Assertions / False Negative Risks / Verdict |
| Technical Feasibility | For each Task: 1) list external dependencies (libraries, OS features, file system assumptions), 2) check if any dependency has platform/version constraints that conflict with Tech Stack, 3) for subprocess-based tests, verify timeout values are sufficient for the operations described, 4) for tests that run commands in tmp_path or isolated dirs, trace whether the command will behave correctly outside the project root (e.g. pytest rootdir detection, missing config files). Flag only concrete blockers, not theoretical risks. | Dependency + constraint audit | Blockers / Platform Risks / Verdict |
| Security | For each Task that touches file I/O, subprocess, or signal handling: 1) trace data flow from external input to execution, 2) check for path traversal, command injection, or symlink attacks in test fixtures, 3) verify temp files use secure creation (tmp_path, not hardcoded paths). | Data flow trace per Task | Injection Surfaces / Unsafe Patterns / Verdict |
| Compatibility & Rollback | For each modified file in the plan: 1) list existing tests that import or call functions in that file, 2) check if the plan's changes could break those existing tests, 3) verify the plan includes running existing tests (not just new ones). Also: can the plan's changes be reverted with a single `git revert`? | Existing-test impact analysis | Breaking Changes / Revert Safety / Verdict |
| Performance | For each Task involving subprocess or threading: 1) calculate worst-case wall-clock time (timeout × max_iterations × retry count), 2) sum across all Tasks to get total suite time, 3) flag any single test that could exceed 30s without @pytest.mark.slow. Provide concrete numbers, not estimates. | Quantified time budget per Task | Time Budget Table / Slow Test Violations / Verdict |
| Clarity | For each Task's "What to implement" section: 1) attempt to write the function signature and key assertions from the description alone (without reading source), 2) flag any Task where you cannot determine the exact test structure from the description. A clear plan = an executor agent can implement without reading source first. | Implementability dry-run | Ambiguous Tasks / Missing Specs / Verdict |

### Pre-mortem Analysis

Before selecting review angles, assume the plan has already been executed and **failed**. Identify the 3 most likely failure causes:

1. **Integration risks** — will the changes break existing behavior or conflict with other components?
2. **Assumption risks** — what implicit assumptions might be wrong? (e.g. file format, API behavior, execution order)
3. **Environment risks** — will this work across all target environments? (e.g. CI, different OS, missing dependencies)

For each risk, formulate a concrete verifiable question. Inject these as "Specific Questions" in each reviewer's dispatch query (see Dispatch Query Template below).

### Angle Selection

Every round: 2 fixed + 2 random = 4 reviewers (one parallel batch, no overflow).

Random selection: sample 2 from the random pool. Repeats across rounds are fine — the same angle reviewing a revised plan catches regressions and verifies fixes.

### Dispatch Query Template

Each reviewer query MUST include: Context (Goal, Non-Goals, key design decisions), Mission (angle-specific from table above), files to read, and anti-patterns.

```
## Context
Goal: [one sentence from plan header]
Non-Goals: [from plan header]
Key design decisions that reviewers might mistake for gaps:
- [decision 1 — what was chosen and what was intentionally excluded]
- [decision 2]

## Your Mission
This is a PLAN REVIEW (Mode 1 in your prompt).
[angle-specific mission from the table above]

## Read These Files
Plan: [path]
Source files referenced in plan: [list — reviewer must read before claiming code behavior]

## Anti-patterns (do NOT do these)
- Do not flag issues outside the stated Goal/Non-Goals
- Do not suggest alternative approaches that are equally valid
- Do not flag missing implementation details that an executor agent can infer
- [plan-specific anti-patterns if any]

## Specific Questions for This Plan
Answer each question with evidence (file:line or shell output). Unanswered = review REJECTED.
1. [risk question identified by main agent]
2. [risk question identified by main agent]

## Source Reading Canary
Answer this BEFORE your analysis. Wrong answer = review REJECTED.
Q: [question only answerable by reading specific source file, e.g. "What is the first line of function X in file Y?"]

## Mandatory Source Reading
Before making ANY claim about code behavior, you MUST:
1. Read the actual source file (use Bash: cat <file>)
2. Cite the specific line number in your finding
3. If you haven't read the file, do NOT speculate — read it first
Findings about code behavior without file:line citations will be discarded.

## Output Requirements
Your last line MUST be exactly one of:
  Verdict: APPROVE
  Verdict: REQUEST CHANGES
Missing verdict = review REJECTED and will be re-dispatched.
```

### Orchestration

1. Compose the round: Goal Alignment + Verify Correctness + 2 random angles
2. Dispatch 4 reviewer subagents in ONE `use_subagent` call (`dangerously_trust_all_tools: true` for each). Each reviewer query = review angle mission + plan file path. Reviewer reads the file itself (has read/shell tools). Do NOT paste plan content into query — it bloats payload and breaks 4-way parallelism. **Must pass plan file path, not content.** **Must specify `agent_name: "reviewer"`**. Same `agent_name` can spawn multiple instances in parallel. **Include in each query:** "Read the source files referenced in the plan before making claims about code behavior."
4. Reviewers in the same round do NOT see each other's feedback
5. Collect all verdicts. If ANY reviewer REJECTs → fix issues → next round (re-sample 2 random angles)
   **Verdict enforcement:** If a reviewer's output does not end with `Verdict: APPROVE` or `Verdict: REQUEST CHANGES`, treat it as malformed → re-dispatch that single angle.
6. **Round 2+ rule:** When re-dispatching after fixes, include in each query a "Rejected Findings" section with one-line summaries of findings rejected in previous rounds and why. Reviewers must not re-raise these.
   **Round 2+ reviewer count:** Dispatch only 2 reviewers (the 2 fixed angles: Goal Alignment + Verify Correctness). Do NOT sample random angles in Round 2+. Purpose of Round 2+ is to verify fixes, not discover new issues.
7. Repeat until all APPROVE in a single round, or 3 rounds reached
8. After 3 rounds: stop and tell user "Plan too complex for automated review. Consider breaking into smaller plans."

### Reviewer Calibration

Reviewers should REJECT only for issues that would cause the plan to fail or produce wrong results. Do NOT reject for:
- Style preferences or alternative approaches that are equally valid
- Theoretical risks that are unlikely in practice
- Missing features that are nice-to-have but not required for the plan's stated goal

The bar is "would this plan produce a 90/100 result?" not "is this plan perfect?"

### Conflict Resolution

When reviewers give contradictory feedback:
1. Main agent compares both arguments against the plan's **Goal** statement (the one-sentence goal in the plan header)
2. The argument that directly serves the stated Goal wins
3. Document the conflict, both arguments, and the resolution in the plan's Review section
4. If both arguments equally serve the goal, ask the user to decide

### Resource Constraints

- **Max parallel subagents per batch**: 4 (tool hard limit). Round 1: 4 reviewers. Round 2+: 2 reviewers (fixed angles only).
- **Reviewer context isolation**: Reviewers in the same round do NOT see each other's feedback. Each gets the full plan.
- **Context size**: Review packet = full plan file content (verbatim). Reviewers need complete task details, code blocks, and file paths to avoid false rejections from incomplete information.
- **Error handling**: If a reviewer crashes or returns malformed output, continue with remaining reviewers. If fewer than half of the round's reviewers complete, restart the round. Malformed = missing Mission/Findings/Verdict structure.

## Phase 2: Execution

After plan is reviewed and approved, choose execution strategy based on checklist size:

### Execution Disciplines

These rules apply regardless of which execution strategy is chosen.

#### Session Resume Protocol

When starting or resuming execution (including new sessions):
1. Read the plan's Goal + Architecture + Non-Goals
2. Run `git diff --stat` to see what's already changed
3. Check checklist: which items are `[x]` done, which `[ ]` remain
4. Write a one-line status summary to the plan's `## Findings` section

This ensures the agent has full context before making any changes.

#### Read Before Decide

Before any of these actions, re-read the plan's **Goal** and **Non-Goals**:
- Changing implementation approach mid-task
- Deciding to skip or reorder a task
- Encountering a blocker and choosing a workaround
- Adding scope not in the original plan

This pushes the original intent back into the attention window, preventing drift after many tool calls.

#### Periodic Re-orientation

Every 3 completed tasks, re-read the plan's **Goal** paragraph. No writing needed — purely attention refresh. This counters gradual context decay in long execution sessions.

#### 3-Strike Error Protocol

When an error occurs during execution:

**Strike 1 — Diagnose & Fix:** Read error carefully, identify root cause, apply targeted fix. Log to `## Errors`.

**Strike 2 — Alternative Approach:** Same error? Try a fundamentally different method. Different tool, different algorithm, different angle. Log to `## Errors`.

**Strike 3 — Broader Rethink:** Question assumptions. Search for solutions. Consider whether the plan itself needs revision. Log to `## Errors`.

**After 3 strikes:** Stop and escalate to user. Explain what was tried, share the specific errors, ask for guidance. Do NOT attempt a 4th time with the same approach.

Rules:
- `next_action != failed_action` — never repeat the exact same failing approach
- Each strike must be logged in the plan's `## Errors` table with attempt number
- Strike count is per-error-type, not global (different errors get their own 3 strikes)

### Execution Strategy

Sequential execution: one task at a time, commit after each.

1. Load plan, identify next unchecked item
2. Execute task (implement + test + verify)
3. Check off item, commit
4. Continue to next. Repeat until done.

Each ralph loop iteration spawns a fresh CLI with clean context. The agent should complete as many tasks as possible per iteration before context fills up.

## Phase 3: Completion

After all tasks done:
1. Run full test suite
2. Present options: merge locally / create PR / keep branch / discard
3. Clean up worktree if applicable

## When to Stop and Ask

- Hit a blocker (missing dependency, unclear instruction)
- Verification fails repeatedly
- Plan has critical gaps
- Don't force through blockers — stop and ask.
