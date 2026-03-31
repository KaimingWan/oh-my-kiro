# Evaluator: Independent Code Quality Assessment

**Goal:** Add an independent evaluator agent (separate from reviewer) that assesses implemented code quality via parallel subagents with mandatory structured evidence, both as a Ralph Loop post-completion stage and as a standalone `@evaluate` command.
**Non-Goals:** Changing the plan/review workflow; modifying how checklist items are verified during execution; adding UI testing (Playwright etc); replacing the existing reviewer agent.
**Architecture:** 4 parallel evaluator subagents (one per dimension group), each with mandatory fill-table prompts and canary questions. Two entry points: Ralph Loop auto-runs after QA; `@evaluate` is a standalone MCP prompt + command. Ralph Loop evaluator runs up to 3 rounds of evaluate→fix→evaluate (GAN-inspired adversarial loop).
**Tech Stack:** Python (ralph_loop.py), Markdown (command file), Python (mcp-prompts.py)
**Work Dir:** worktrees/omk-evaluator

## Design Decisions

### Why separate from Reviewer
- Reviewer evaluates **plans** (未写的代码) — logic, completeness, verify commands
- Evaluator evaluates **implementations** (已写的代码) — quality, security, alignment
- Different inputs, different criteria, different personas
- Sharing would dilute both roles

### Why 4 parallel subagents (not 1 serial)
- Matches existing plan review pattern (4 parallel reviewers)
- Each subagent has fresh context — no self-evaluation bias
- Fits kiro's 4-subagent parallel limit

### Why mandatory tables (anti-走过场)
- Anthropic found evaluators "identify issues then talk themselves into approving anyway"
- Mandatory tables force concrete evidence (file:line citations)
- Empty/missing rows = REJECTED, re-dispatch
- Canary questions verify source code was actually read

### GAN-inspired adversarial loop
- FAIL → Generator fixes → fresh Evaluator re-evaluates (up to 3 rounds)
- Each round's Evaluator is fresh context (no "already FAIL'd, awkward to FAIL again" bias)
- Prevents over-complexity: Simplicity dimension has highest weight

## Review
<!-- Reviewer writes here -->

### Task 1: Evaluator prompt template with mandatory tables

**Files:**
- Create: `commands/evaluate.md`

Create the evaluator dispatch command. The core of this task is the **mandatory structured evidence** mechanism — each subagent MUST fill specific tables, empty tables = REJECTED.

**4 subagent dimension groups:**

**Subagent #1: "Refactoring Expert" — Simplicity + Maintainability**
Persona: A senior engineer who believes the best code is code that doesn't exist. Your job is to find things to delete or simplify.
- List all functions > 50 lines → fill table: `| Function | Lines | Can split? | Split plan | Reason if not |`
- List all try/except blocks → fill table: `| Location | Catches what | Necessary? | What if removed |`
- List all abstraction layers → fill table: `| Layer | Purpose | Callers | Can flatten? |`
- Empty table = REJECTED

**Subagent #2: "Product Manager" — Alignment**
Persona: You don't care about code quality — you only care whether what was built matches what was asked for. Every deviation from the plan is a bug.
- Copy each Goal line from plan → fill table: `| Goal item | Code location (file:line) | Implemented? | Evidence |`
- Copy each Non-Goal → fill table: `| Non-Goal item | Code doing this? | file:line if yes |`
- Check for scope creep: anything implemented that plan didn't ask for
- Missing rows = REJECTED

**Subagent #3: "Breaker" — Correctness + Robustness**
Persona: Your job is to break the code. Construct inputs that crash it, confuse it, or make it produce wrong results. You succeed when you find a bug.
- For each modified function, construct a malicious/edge input → fill table: `| Function | Evil input | Expected behavior | Actual behavior | Bug? |`
- "All functions are fine" is NOT valid output — must find ≥1 edge case
- Check error paths: `| file:line | Error path | Tested by? | Reachable? |`
- Empty table = REJECTED

**Subagent #4: "CSO" — Security**
Persona: Chief Security Officer running OWASP Top 10 + STRIDE threat model. Only report findings with confidence ≥ 8/10. False positives waste everyone's time — if you're not sure, don't report it.
- Run `grep -rn 'subprocess\|eval\|exec\|open(\|os.system' <modified files>` → fill table: `| file:line | Call | Input source | Injectable? | Confidence (1-10) | Fix |`
- Check for hardcoded secrets, path traversal, command injection
- If grep returns 0 matches, state that explicitly (not just skip)
- Only report findings with confidence ≥ 8/10
- Empty table = REJECTED

**Each subagent also gets:**
- Source Reading Canary question (must read code to answer)
- Severity classification: CRITICAL / HIGH / MEDIUM / LOW per finding
- Final line MUST be: `Verdict: PASS` or `Verdict: FAIL`
- Missing verdict = malformed → re-dispatch

**Aggregation rule:** Any subagent FAIL or any CRITICAL finding → overall FAIL.

### Task 2: MCP prompt registration

**Files:**
- Modify: `scripts/mcp-prompts.py`

Add `EVALUATE_PROMPT` constant and `def evaluate(content)` function following existing pattern. The prompt reads `commands/evaluate.md` and dispatches 4 parallel evaluator subagents with the user's scope as context.

### Task 3: Ralph Loop evaluator stage

**Files:**
- Modify: `scripts/ralph_loop.py`

After the existing QA stage passes and before the completion review, add an evaluator stage:

1. Build evaluator prompt: plan Goal/Architecture + `git diff --stat` + evaluation criteria
2. Dispatch 4 parallel evaluator subagents via kiro-cli (same pattern as existing `completion_review`)
3. Parse each subagent output for Verdict
4. If any FAIL or CRITICAL: feed findings to a generator round (spawn kiro-cli with fix prompt)
5. Re-evaluate with fresh evaluator subagents (up to 3 evaluate→fix cycles)
6. If PASS or max cycles reached: proceed to completion review

Add `RALPH_SKIP_EVAL=1` env var to skip. Use `timeout=300` matching existing QA pattern.

Extract evaluator subprocess call into a testable function `run_evaluator()` for mockability.

### Task 4: Regression tests

**Files:**
- Create: `tests/ralph-loop/test_evaluator.py`

Test the evaluator integration in ralph_loop.py:
- Test that evaluator stage runs after QA when enabled
- Test that `RALPH_SKIP_EVAL=1` skips the stage
- Test that evaluator FAIL triggers a fix round
- Test max 3 eval cycles then proceed
- Test CRITICAL finding → overall FAIL

**Mock strategy:** Extract `run_evaluator()` as a testable function. Use `unittest.mock.patch` to mock it returning PASS/FAIL verdicts. For integration tests, use `RALPH_KIRO_CMD="echo PASS"` / `"echo FAIL"`.

## Checklist

- [x] `commands/evaluate.md` exists with 4 subagent dispatch and mandatory tables | `test -f commands/evaluate.md && grep -q 'REJECTED' commands/evaluate.md`
- [ ] Evaluate prompt has all 6 dimensions across 4 subagents | `grep -q 'Simplicity' commands/evaluate.md && grep -q 'Alignment' commands/evaluate.md && grep -q 'Correctness' commands/evaluate.md && grep -q 'Security' commands/evaluate.md && grep -q 'Robustness' commands/evaluate.md && grep -q 'Maintainability' commands/evaluate.md`
- [ ] Evaluate prompt has mandatory table format with REJECTED enforcement | `grep -c 'REJECTED' commands/evaluate.md | xargs test 3 -le`
- [ ] Evaluate prompt has canary question mechanism | `grep -qi 'canary' commands/evaluate.md`
- [ ] Evaluate prompt has severity classification | `grep -q 'CRITICAL' commands/evaluate.md && grep -q 'HIGH' commands/evaluate.md`
- [ ] `mcp-prompts.py` has `evaluate` function registered | `grep -q 'def evaluate' scripts/mcp-prompts.py`
- [ ] Ralph Loop has evaluator stage after QA | `grep -q 'run_evaluator\|eval_stage\|RALPH_SKIP_EVAL' scripts/ralph_loop.py`
- [ ] `RALPH_SKIP_EVAL=1` skips evaluator stage | `grep -q 'RALPH_SKIP_EVAL' scripts/ralph_loop.py`
- [ ] Evaluator extracted as testable function | `grep -q 'def run_evaluator' scripts/ralph_loop.py`
- [ ] Regression tests exist | `test -f tests/ralph-loop/test_evaluator.py`
- [ ] Evaluator tests pass | `cd /Users/wanshao/project/gtm/worktrees/omk-evaluator && python3 -m pytest tests/ralph-loop/test_evaluator.py -v`
- [ ] 回归测试通过 | `cd /Users/wanshao/project/gtm/worktrees/omk-evaluator && python3 -m pytest tests/ralph-loop/ -v`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## QA

```bash
cd /Users/wanshao/project/gtm/worktrees/omk-evaluator && python3 -m pytest tests/ralph-loop/ -v
```
