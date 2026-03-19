---
name: omk-reviewing
description: "Code and plan review with multi-angle dispatch. Trigger when user says 'review', 'code review', 'check my code', 'PR review', '@review', or when completing a plan phase that requires review. Also trigger before merge, after major feature completion, or when user asks for feedback on implementation quality."
---

## Trigger Examples
- "@review 看看这个 PR"
- "帮我 review 一下这段代码"
- "check my implementation before I merge"
- "review the plan I just wrote"
- "这个改动有没有问题？"

# Reviewing — Request, Execute, Receive

## Requesting Review

**When (mandatory):** after completing major feature, before merge, after each task batch.

### Plan Review — 4 angles, 4 parallel subagents

#### Pre-review Risk Identification
Before dispatching reviewers, the main agent MUST run the **Pre-mortem Analysis** defined in `skills/planning/SKILL.md` (Phase 1.5 → Pre-mortem Analysis section). This produces 3 risk questions (Integration / Assumption / Environment) that are injected as "Specific Questions" into each reviewer's dispatch query.

Additionally, craft one canary question per dispatch that requires reading a specific source file.

#### Dispatch

Dispatch exactly **4 reviewer subagents in parallel** (`agent_name: "reviewer"`), one per angle:

| # | Angle | Mission |
|---|-------|---------|
| 1 | Goal Alignment | Every task maps to goal? Execution order valid? Non-goals respected? |
| 2 | Verify Correctness | Each verify command sound? False positives/negatives? |
| 3 | Completeness | All modified files covered? Edge cases? Conflicts with other plans? |
| 4 | Technical Feasibility | Blockers? Contradictions? Race conditions? Signal safety? |

Each subagent query must include: plan file path + relevant source file paths to read.

### Deterministic Pre-check (main agent, before dispatching reviewers)

Before dispatching any reviewer subagent, the **main agent** runs deterministic checks (reviewer subagent only has read/write/shell — no LSP tools):

1. Run `get_diagnostics` on all modified files — collect compiler errors/warnings
2. Run `pattern_search` for known anti-patterns (bare except, subprocess without timeout, etc.)
3. Package results as "Pre-check Findings" to include in each reviewer's dispatch query

Pre-check findings are automatically P0/P1 — they don't need LLM judgment. This reduces the reviewer's workload to reasoning-heavy issues only.

### Code Review — size-based dispatch

Choose dispatch mode based on diff size:

**Small PR (<200 lines diff):** Dispatch **1 reviewer subagent** (`agent_name: "reviewer"`) with:
- What was implemented
- Plan/requirements reference
- Git diff range (BASE_SHA..HEAD_SHA)
- Pre-check Findings from Deterministic Pre-check

**Large PR (≥200 lines diff):** Dispatch **2 reviewer subagents in parallel** (`agent_name: "reviewer"`):

| Agent | Angle | Focus |
|-------|-------|-------|
| 1 | Correctness + Security | Functional correctness, input validation, auth, injection, race conditions |
| 2 | Quality + Architecture | SOLID, code smells, performance, error handling, boundary conditions |

Each agent receives: diff range, pre-check findings, and relevant source file paths. Findings from both agents are merged and deduplicated by the main agent before presenting to user.

## Iron Principle: Respect the Existing Codebase

> The existing code is the stable, battle-tested baseline. It may be 85/100 — not perfect — but it works. Your job is to review the **new code**, not to fix the old code through the PR author.

- **Only review new/changed lines.** Do not raise findings against unchanged existing code, even if it has style issues, minor inefficiencies, or non-ideal patterns.
- **Judge new code by the standards of the existing codebase**, not by textbook perfection. If the existing code uses `@Autowired` field injection, don't flag the new code for not using constructor injection. If the existing code swallows certain exceptions with a warn log, the new code doing the same is consistent, not a bug.
- **P2/P3 "style improvement" findings on existing patterns are noise.** Only raise findings on existing code if it's P0/P1 (security vulnerability, data loss, crash) AND directly touched by the PR.
- **"While we're here" refactors are out of scope.** If the reviewer wants to suggest improving old code, it goes in a separate follow-up issue, not as a PR comment blocking merge.

## Executing Code Review (for reviewer agent)

### 1) Preflight context

- Run `git diff --stat` then `git diff` to understand scope
- If diff > 500 lines, batch by file/module — review each batch separately
- Note: file renames, new files, deleted files

### 2) SOLID + architecture check

- Load `references/solid-checklist.md` for coverage
- Check SRP, OCP, LSP, ISP, DIP violations
- Flag common code smells: long methods, feature envy, data clumps, dead code
- Apply refactor heuristics where applicable

### 3) Security scan

- Load `references/security-checklist.md` for coverage
- Check: input/output safety (XSS, injection, SSRF, path traversal), auth gaps, secrets in code
- Check: race conditions (concurrent access, check-then-act, TOCTOU, missing locks)
- Call out both **exploitability** and **impact**

### 4) Code quality scan

- Load `references/code-quality-checklist.md` for coverage
- Check: error handling (swallowed exceptions, overly broad catch, async errors)
- Check: performance (N+1 queries, CPU-intensive ops in hot paths, missing cache, unbounded memory)
- Check: boundary conditions (null/undefined, empty collections, numeric boundaries, off-by-one)
- Flag issues that may cause silent failures or production incidents

### 5) Removal candidates

- Load `references/removal-plan.md` for template
- Identify dead code, unused imports, deprecated patterns
- Categorize: safe to remove now vs defer with plan

### 6) Output

- Load `references/output-format.md` for structure
- Categorize findings: P0 Critical / P1 High / P2 Medium / P3 Low
- Be specific — cite file:line, show code examples
- Never rubber-stamp

### 7) Next steps confirmation

- Present findings summary with issue counts by priority
- Ask user how to proceed (fix all / P0-P1 only / specific items / no changes)
- Do NOT implement changes until user explicitly confirms

## Receiving Review

**Core principle:** Verify before implementing. Technical correctness over social comfort.

1. READ complete feedback without reacting
2. UNDERSTAND — restate requirement (or ask)
3. VERIFY against codebase reality
4. EVALUATE — technically sound for THIS codebase?
5. RESPOND — technical acknowledgment or reasoned pushback
6. IMPLEMENT one item at a time, test each

### YAGNI Check

Before implementing any suggestion, ask: "Does this solve a real problem we have now?" Reject speculative generality, premature abstractions, and features for hypothetical future needs.

### Implementation Order

When implementing accepted feedback:
1. **Blocking issues first** — anything that breaks build/tests
2. **Simple fixes** — typos, naming, formatting (quick wins)
3. **Complex changes** — refactors, architecture changes (highest risk, do last)

### Push Back

Push back when reviewer is wrong — with technical reasoning and evidence. Show code, show tests, show docs.

### Acknowledging Correct Feedback

When feedback is correct, acknowledge briefly and implement: "Agreed, fixing." No flattery.

**Never:** "You're absolutely right!" / "Great point!" / implement before verifying.
