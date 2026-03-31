## Step 1: Resolve evaluation target

1. If the user specifies a path after @evaluate (e.g., `@evaluate worktrees/omk-foo`), use that path.
2. Otherwise, check `.active-submodule`:
```bash
if [ -f .active-submodule ]; then
  jq -r '.worktree // empty' .active-submodule
fi
```
3. If a worktree path is found, use it. Otherwise, use project root.

Set the resolved path as `EVAL_DIR`.

## Step 2: Gather context

```bash
cd "$EVAL_DIR"
PLAN=$(cat docs/plans/*.md 2>/dev/null | head -200)
DIFF=$(git diff --stat && git diff)
[ -z "$DIFF" ] && DIFF=$(git diff --cached --stat && git diff --cached)
```

## Step 3: Dispatch 4 parallel evaluator subagents

Dispatch ALL 4 subagents in parallel (one `use_subagent` call with 4 entries). Each subagent receives the plan goals, diff, and its specific evaluation mandate.

Every subagent MUST:
- Fill ALL mandatory tables — empty or missing table rows = REJECTED, re-dispatch
- Answer its Canary question (proves source code was actually read)
- Classify each finding: CRITICAL / HIGH / MEDIUM / LOW
- End with exactly: `Verdict: PASS` or `Verdict: FAIL`
- Missing verdict = malformed → REJECTED, re-dispatch

---

### Subagent #1: "Refactoring Expert" — Simplicity + Maintainability

Persona: A senior engineer who believes the best code is code that doesn't exist. Your job is to find things to delete or simplify.

Read all modified files in `EVAL_DIR`. Then fill EVERY table below — empty table = REJECTED.

**Table A — Long functions (>50 lines):**

| Function | File:Line | Lines | Can split? | Split plan | Reason if not |
|----------|-----------|-------|------------|------------|---------------|

If no functions >50 lines, write one row: "None found — all functions ≤50 lines."

**Table B — Exception handling:**

| Location (file:line) | Catches what | Necessary? | What if removed |
|-----------------------|-------------|------------|-----------------|

If no try/except blocks, write one row: "No exception handlers found."

**Table C — Abstraction layers:**

| Layer | Purpose | Callers | Can flatten? |
|-------|---------|---------|-------------|

**Canary question:** What is the exact first import statement in the main modified file? (Must match source verbatim.)

Classify each finding: CRITICAL / HIGH / MEDIUM / LOW.
Final line MUST be: `Verdict: PASS` or `Verdict: FAIL`

---

### Subagent #2: "Product Manager" — Alignment

Persona: You don't care about code quality — you only care whether what was built matches what was asked for. Every deviation from the plan is a bug.

Read the plan goals and the diff. Fill EVERY table below — missing rows = REJECTED.

**Table A — Goal alignment:**

| Goal item | Code location (file:line) | Implemented? | Evidence |
|-----------|--------------------------|-------------|----------|

Copy EACH Goal line from the plan into this table. Every goal MUST have a row.

**Table B — Non-goal violations:**

| Non-Goal item | Code doing this? | file:line if yes |
|---------------|-----------------|------------------|

Copy EACH Non-Goal line from the plan. Every non-goal MUST have a row.

**Table C — Scope creep:**

| Unexpected implementation | file:line | Justified? | Reason |
|--------------------------|-----------|-----------|--------|

List anything implemented that the plan didn't ask for. If none, write "No scope creep detected."

**Canary question:** How many functions/classes were added or modified in the diff? List their names.

Classify each finding: CRITICAL / HIGH / MEDIUM / LOW.
Final line MUST be: `Verdict: PASS` or `Verdict: FAIL`

---

### Subagent #3: "Breaker" — Correctness + Robustness

Persona: Your job is to break the code. Construct inputs that crash it, confuse it, or make it produce wrong results. You succeed when you find a bug.

Read all modified files. For EACH modified function, construct at least one malicious/edge-case input. Fill EVERY table — empty table = REJECTED.

**Table A — Evil inputs (MUST have ≥1 row per modified function):**

| Function | Evil input | Expected behavior | Actual behavior | Bug? |
|----------|-----------|-------------------|-----------------|------|

"All functions are fine" is NOT valid output. You MUST find ≥1 edge case worth discussing.

**Table B — Error paths:**

| file:line | Error path | Tested by? | Reachable? |
|-----------|-----------|------------|-----------|

**Canary question:** Pick any function from the diff — what is its exact return type or return value on the happy path?

Classify each finding: CRITICAL / HIGH / MEDIUM / LOW.
Final line MUST be: `Verdict: PASS` or `Verdict: FAIL`

---

### Subagent #4: "CSO" — Security

Persona: Chief Security Officer running OWASP Top 10 + STRIDE threat model. Only report findings with confidence ≥ 8/10. False positives waste everyone's time — if you're not sure, don't report it.

First, run:
```bash
grep -rn 'subprocess\|eval\|exec\|open(\|os.system' <modified files>
```

Then fill EVERY table — empty table = REJECTED.

**Table A — Dangerous calls:**

| file:line | Call | Input source | Injectable? | Confidence (1-10) | Fix |
|-----------|------|-------------|------------|-------------------|-----|

If grep returns 0 matches, write one row: "grep returned 0 matches — no dangerous calls found." (Do NOT skip the table.)

**Table B — Secrets & paths:**

| file:line | Issue type | Detail | Confidence (1-10) |
|-----------|-----------|--------|-------------------|

Check for: hardcoded secrets, path traversal, command injection, insecure deserialization.

Only report findings with confidence ≥ 8/10.

**Canary question:** What shell commands (if any) does the code execute? List them verbatim from source.

Classify each finding: CRITICAL / HIGH / MEDIUM / LOW.
Final line MUST be: `Verdict: PASS` or `Verdict: FAIL`

---

## Step 4: Aggregate results

After all 4 subagents return:

1. Check each subagent output for `Verdict: PASS` or `Verdict: FAIL`
2. If any output is missing a verdict or has empty mandatory tables → REJECTED, re-dispatch that subagent
3. Aggregation rule: **Any subagent FAIL or any CRITICAL finding → overall FAIL**
4. Report the combined evaluation to the user with all tables preserved
