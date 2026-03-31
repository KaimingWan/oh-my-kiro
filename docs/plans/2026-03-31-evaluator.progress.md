# Evaluator Plan Progress

## Iteration 1 — 2026-03-31T12:06

- **Task:** Create `commands/evaluate.md` with 4 parallel subagent dispatch, mandatory tables, canary questions, severity classification, and REJECTED enforcement
- **Files changed:** `commands/evaluate.md` (created), `docs/plans/2026-03-31-evaluator.md` (checked item 1)
- **Learnings:**
  - Pre-existing env issue: `tests/test_debugging_skill.py` references `skills/debugging/SKILL.md` but actual path is `skills/omk-debugging/SKILL.md` — not related to evaluator work
  - Pre-existing ralph-loop test failures (2) due to lock file contention — not related
  - Plan QA targets `tests/ralph-loop/` specifically, which runs (94 pass, 2 pre-existing fail)
  - The hook that guards checklist marking requires the verify command to be run via `execute_bash` immediately before the `str_replace`
  - All 5 Task 1 checklist items (items 1-5) pass verification against the created file, but only item 1 was marked per iteration rules
- **Status:** done

## Iteration 2 — 2026-03-31T12:12

- **Task:** Mark Task 1 remaining items (dimensions, REJECTED, canary, severity) + implement Task 2 (MCP prompt registration)
- **Files changed:** `scripts/mcp-prompts.py` (added EVALUATE_PROMPT + evaluate function), `docs/plans/2026-03-31-evaluator.md` (marked items 2-6)
- **Learnings:**
  - Items 2-5 (all 6 dimensions, REJECTED enforcement, canary, severity) were already implemented in iteration 1 when `commands/evaluate.md` was created — just needed verify + mark
  - MCP prompt pattern: constant `XXX_PROMPT` with `{content}` placeholder + `@mcp.prompt()` decorated function that calls `.replace("{content}", content or "fallback")`
  - The evaluate prompt in mcp-prompts.py is intentionally minimal — it references `commands/evaluate.md` for the full dispatch logic, keeping the prompt DRY
- **Status:** done

## Iteration 3 — 2026-03-31T12:15

- **Task:** Implement Task 3 (evaluator stage in ralph_loop.py) + Task 4 (regression tests)
- **Files changed:** `scripts/ralph_loop.py` (added `run_evaluator()` function, `skip_eval` in Config, evaluator stage between QA and completion review), `tests/ralph-loop/test_evaluator.py` (created, 7 tests), `tests/ralph-loop/test_ralph_loop.py` (added `RALPH_SKIP_EVAL=1` to test helper default env)
- **Learnings:**
  - `test_main_has_no_inline_env_reads` enforces that all `os.environ.get` calls in `main()` go through `Config`/`parse_config` — must add new env vars to the dataclass, not read inline
  - Existing tests use `RALPH_SKIP_REVIEW=1` to skip completion review; needed to add `RALPH_SKIP_EVAL=1` to the test helper's default env to prevent evaluator from running in unrelated tests (caused `test_already_complete` to hang trying to spawn real kiro-cli)
  - `run_evaluator` is a module-level function (not nested in `main()`) for testability — matches the pattern of `completion_review` being a nested function but `run_evaluator` needs to be importable for unit tests
  - Mock strategy: `unittest.mock.patch("scripts.ralph_loop.subprocess.run")` with side_effect list to control git diff + evaluator + fix round responses
- **Status:** done
