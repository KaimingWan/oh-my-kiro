---
name: omk-coding
description: "Enforces coding best practices: deep-read before modify, LSP-first navigation, TDD red-green-refactor, minimal changes, self-review, verification. Trigger when writing code, modifying source files, fixing bugs, refactoring, optimizing code, entering a worktree or submodule, or when user says 'write code', 'implement', 'fix this', 'fix PR', 'add feature', 'add field', 'refactor', 'optimize', 'modify', 'change this', 'update code', 'apply feedback', 'apply review', '改代码', '修复', '加个', '改一下', '优化'. Also trigger when creating/editing .java .py .ts .js .go .rs .sh .tsx .jsx .vue .css .scss files, or after debugging identifies root cause and implementation begins."
---

# Coding — Write Code Right

## Trigger Examples
- "帮我实现这个功能"
- "fix this bug in the auth module"
- "重构一下这段代码"
- "修复 PR review 发现的问题"
- "改一下这个 hook 的逻辑"
- "apply the review feedback"
- "优化这段代码的性能"
- "加个字段到这个 model 里"

## Overview

Writing code without discipline creates debt. This skill enforces quality at the point of creation.

**Core principle:** Every code change must be minimal, tested, verified, and self-reviewed before claiming done.

## Phase 0: Environment Setup

Before writing any code in a worktree or submodule:

```
1. Initialize LSP for semantic analysis:
   /code init

2. Get project overview:
   generate_codebase_overview

3. Detect language & build system:
   - Java → find pom.xml / build.gradle → note test command (mvn test / gradle test)
   - TypeScript/JS → find package.json → note test command (npm test / vitest / jest)
   - Python → find pyproject.toml / pytest.ini → note test command (pytest)
   - Rust → Cargo.toml → cargo test
   - Go → go test ./...

4. Run existing tests to establish baseline:
   <detected test command>
   Record: N tests, M passing, K failing
```

**If LSP init fails:** Retry with `/code init -f`. If still fails, log to plan Errors and continue with grep fallback — but note degraded analysis quality.

## Phase 0.5: Deep Read — Build Understanding (MANDATORY)

> **This phase is NOT optional.** Even for "simple" changes, you MUST complete it before writing any code.
> Research shows: the most expensive failure mode is code that is "correct in isolation but breaks the surrounding system" (Boris Tane). Agents only explore dependencies 42% of the time when left to decide on their own (CodeCompass). This phase forces the other 58%.

```
1. goto_definition — navigate to the code you'll change, read it deeply (not skim)

2. find_references — map ALL callers and dependents of the symbols you'll modify
   Output: list of files and functions that call/use the target code

3. get_document_symbols — understand the internal structure of files you'll modify
   Output: key types, functions, constants in each file

4. Read adjacent code — other files in the same module/package
   Look for: naming conventions, error handling patterns, test patterns, shared utilities

5. get_diagnostics — record current state (zero new errors allowed after your change)

6. Synthesize a Codebase Understanding summary (output this explicitly):

   Codebase Understanding:
   - Module role: [what this module does in the system]
   - File structure: [key symbols in the files you'll modify]
   - Callers: [who calls the code you'll modify]
   - Dependencies: [what the target code depends on]
   - Conventions: [code style, naming, error handling patterns]
   - Impact scope: [which other files/modules could be affected by your change]

7. Signal completion:
   touch /tmp/omk-coding-deep-read-done
```

**If you cannot answer any field in the Codebase Understanding summary**, you haven't read enough code. Go back and read more before proceeding.

## Phase 1: Understand Before Changing

Before modifying any file, confirm you completed Phase 0.5 and that your Codebase Understanding covers the target code.

**Rules (Iron Rules — no exceptions):**
- No modify without goto_definition
- No refactor without find_references
- No new public API without searching for existing similar abstractions
- Match existing code style — don't introduce new conventions

## Phase 2: Write Code (TDD)

### Red → Green → Refactor

```
Step 1: Write failing test FIRST
  - Test names: methodName_condition_expectedResult
  - One behavior per test
  - Run test → must FAIL (red)

Step 2: Write minimal implementation
  - Solve ONLY what the test requires
  - No speculative features (YAGNI)
  - No premature abstraction

Step 3: Run test → must PASS (green)

Step 4: Refactor if needed
  - Extract only when duplication is real (not imagined)
  - Run tests again → still PASS
```

### Minimal Change Rules

| Rule | Check |
|------|-------|
| Single responsibility | Does this change do exactly one thing? |
| Minimal diff | Can any line be removed without breaking the goal? |
| No drive-by fixes | Unrelated improvements go in separate commits |
| No new dependencies | Unless essential and approved |
| Backward compatible | Existing callers unaffected unless explicitly intended |

### Code Quality Gates

- Methods ≤ 20 lines (split when longer)
- No boolean flag parameters — split into two methods
- No swallowed exceptions — catch must log or rethrow
- Return empty collections, not null
- Use self-documenting names — comments explain WHY, not WHAT
- Depend on interfaces, not concrete implementations

## Phase 3: Self-Verify

After implementation, before claiming done:

```
1. Run full test suite (not just new tests):
   <project test command>
   → Must show 0 new failures

2. Run linter/compiler:
   get_diagnostics on all modified files
   → Must show 0 new errors/warnings

3. Check diff scope:
   git diff --stat
   → Every changed file must be intentional

4. Regression check:
   - New test passes? → Revert your fix → test must FAIL → restore fix
   - This proves the test actually tests your change
```

### Frontend Visual Verification (when UI files changed)

If any modified file is a frontend file (.tsx/.jsx/.vue/.html/.css/.scss), you MUST verify visually:

```
1. Ensure dev server is running (check with curl or ps)
2. Use agent-browser to screenshot the affected page:
   agent-browser open http://localhost:<port>/<path> && agent-browser wait --load networkidle && agent-browser screenshot --annotate
3. Review the screenshot — does it match the expected behavior?
4. If the visual result is wrong, fix and re-verify. Do NOT claim done without visual confirmation.
5. For style/layout issues, use agent-browser snapshot -i to inspect element structure
```

**CRITICAL:** Never claim a frontend issue is "fixed" based only on code changes. The browser is the source of truth.

## Phase 4: Self-Review

Before committing, review your own diff:

```
1. git diff (staged or unstaged)

2. For each changed file, check:
   □ SRP — one reason to change?
   □ No dead code introduced
   □ Error paths handled (what if this fails?)
   □ Boundary conditions (null, empty, zero, max)
   □ No hardcoded values — use constants/config
   □ Thread safety (if concurrent context)

3. Ask yourself:
   - "What breaks if I revert this?"
   - "What breaks if input is unexpected?"
   - "Would a new team member understand this?"
```

**If any check fails:** Fix before committing. Don't leave TODOs for "later."

## Phase 5: Commit

```bash
# Verify one last time
<test command>

# Commit with descriptive message
git add -p  # stage intentionally, not git add .
git commit -m "<type>: <what changed and why>"
```

Commit message types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

## Language-Specific Addenda

### Java
- Load `knowledge/reference/java-coding-standards.md` when touching .java files
- After interface changes: `mvn compile -pl <module> -am`
- After all changes: `mvn clean test`
- Prefer constructor injection over @Autowired

### TypeScript/JavaScript
- Strict mode, no `any` unless justified
- Prefer `const` over `let`, never `var`
- Handle async errors — no unhandled promise rejections

### Python
- Type hints on all public functions
- `pytest` with `-v` flag for visibility
- No bare `except:` — always specify exception type

## When to Apply

**Always when:**
- Creating new files in a worktree/submodule
- Modifying existing code
- Fixing bugs (TDD: write failing test reproducing bug first)
- Refactoring

**Skip Phase 2 (TDD) only when:**
- Pure documentation changes
- Config-only changes (but still verify)
- User explicitly says "skip tests"

## Anti-patterns

| Don't | Do Instead |
|-------|-----------|
| Write code then "add tests later" | Test first, always |
| `git add .` | `git add -p` — stage intentionally |
| Fix + unrelated cleanup in one commit | Separate commits |
| Trust "it should work" | Run and see output |
| Copy-paste without understanding | Read source, then adapt |
| Add abstraction "for future use" | Solve today's problem |
