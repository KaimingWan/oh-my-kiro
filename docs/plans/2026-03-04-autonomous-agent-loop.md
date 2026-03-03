# Autonomous Agent Loop Enhancement

**Goal:** Make ralph loop agent truly end-to-end autonomous — when encountering obstacles, the agent self-diagnoses, researches, tries alternative approaches, and uses subagents, instead of stopping or skipping.
**Non-Goals:** Rewriting the outer loop architecture (it's already superior to snarktank/ralph). Adding new CLI backends. Changing plan file format.
**Architecture:** Enhance `build_prompt()` with error context injection, autonomous problem-solving instructions, and a "Codebase Patterns" consolidation mechanism borrowed from snarktank/ralph. Add `extract_error_context()` to parse the log file for actionable error info from the previous iteration. Adjust main loop to pass stale/error state into prompt builder.
**Tech Stack:** Python 3, existing scripts/lib/ modules
**Work Dir:** `.`

## Review

### Round 1 (4 reviewers, all REQUEST CHANGES)

**Accepted findings:**
- P0: Task 2 must add `from scripts.lib.error_context import extract_error_context, format_reverted_context` to ralph_loop.py imports
- P0: Verify command #7 uses naive string search (`'stale_rounds=' in src`) — could match comments. Fixed to use `inspect.signature` check instead.
- P0: Plan must explicitly show how `reverted` from `revert_failed_checks()` feeds into next iteration's `build_prompt()` call in main()
- P1: Error regex `Error:` too broad — tightened to require line-start anchoring and added context-window approach (only scan last 100 lines)

**Rejected findings:**
- ~~"Task 1 test imports non-existent module"~~ — this is expected TDD behavior (Step 2 verifies it fails)
- ~~"Task 2 verify checks signature before implementation"~~ — checklist items are verified AFTER implementation, not before

## Tasks

### Task 1: Error Context Extraction

**Files:**
- Create: `scripts/lib/error_context.py`
- Test: `tests/ralph-loop/test_error_context.py`

**Step 1: Write failing test**

```python
# tests/ralph-loop/test_error_context.py
import pytest
from pathlib import Path
from scripts.lib.error_context import extract_error_context

def test_extracts_last_error_from_log(tmp_path):
    log = tmp_path / "test.log"
    log.write_text(
        "normal output\n"
        "Error: module 'foo' has no attribute 'bar'\n"
        "Traceback (most recent call last):\n"
        "  File \"test.py\", line 10\n"
        "AttributeError: module 'foo' has no attribute 'bar'\n"
        "more output\n"
    )
    ctx = extract_error_context(log, max_lines=50)
    assert "AttributeError" in ctx
    assert len(ctx) < 3000

def test_empty_log(tmp_path):
    log = tmp_path / "test.log"
    log.write_text("")
    assert extract_error_context(log) == ""

def test_no_errors(tmp_path):
    log = tmp_path / "test.log"
    log.write_text("all good\nno problems here\n")
    assert extract_error_context(log) == ""

def test_missing_log(tmp_path):
    assert extract_error_context(tmp_path / "nope.log") == ""

def test_reverted_items_context():
    reverted = [(1, "pytest tests/ -v"), (3, "bash -n hook.sh")]
    from scripts.lib.error_context import format_reverted_context
    ctx = format_reverted_context(reverted)
    assert "#1" in ctx
    assert "pytest" in ctx
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_error_context.py -v`
Expected: FAIL (module not found)

**Step 3: Write minimal implementation**

```python
# scripts/lib/error_context.py
"""Extract error context from ralph loop log for next-iteration prompt injection."""
from __future__ import annotations
import re
from pathlib import Path

_ERROR_PATTERNS = re.compile(
    r"^(?:(?:FAIL|FAILED|Traceback|fatal:)|(?:\w+(?:Error|Exception):))",
    re.MULTILINE,
)

def extract_error_context(log_path: Path, max_lines: int = 30) -> str:
    if not log_path.exists():
        return ""
    try:
        text = log_path.read_text(errors="replace")
    except Exception:
        return ""
    if not text.strip():
        return ""
    lines = text.strip().split("\n")
    error_lines: list[str] = []
    in_block = False
    for line in reversed(lines[-200:]):
        if _ERROR_PATTERNS.search(line):
            in_block = True
        if in_block:
            error_lines.append(line)
            if len(error_lines) >= max_lines:
                break
    if not error_lines:
        return ""
    error_lines.reverse()
    return "\n".join(error_lines)[:2500]


def format_reverted_context(reverted: list[tuple[int, str]]) -> str:
    if not reverted:
        return ""
    lines = ["The following items were marked done but their verify commands FAILED (reverted to unchecked):"]
    for idx, cmd in reverted:
        lines.append(f"  #{idx}: `{cmd}` — fix the root cause, don't just re-mark it")
    return "\n".join(lines)
```

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/test_error_context.py -v`
Expected: PASS

**Step 5: Commit**
`feat: add error context extraction for ralph loop prompt injection`

**Verify:** `python3 -m pytest tests/ralph-loop/test_error_context.py -v`

### Task 2: Enhance build_prompt with Autonomous Problem-Solving

**Files:**
- Modify: `scripts/ralph_loop.py`
- Modify: `tests/ralph-loop/test_ralph_loop.py`

**Step 1: Write failing test**

Add to `tests/ralph-loop/test_ralph_loop.py`:

```python
def test_stale_prompt_contains_error_context(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    log_file = tmp_path / "ralph.log"
    log_file.write_text("Error: something broke\nTraceback:\n  File x\nValueError: bad\n")
    prompt = build_prompt(3, pf, plan_file, tmp_path, skip_precheck="1",
                          stale_rounds=2, log_path=log_file)
    assert "STUCK" in prompt or "stuck" in prompt
    assert "alternative approach" in prompt.lower() or "different strategy" in prompt.lower()

def test_reverted_items_in_prompt(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    reverted = [(1, "pytest tests/ -v")]
    prompt = build_prompt(2, pf, plan_file, tmp_path, skip_precheck="1",
                          reverted_items=reverted)
    assert "verify commands FAILED" in prompt
    assert "pytest" in prompt

def test_normal_prompt_has_autonomous_instructions(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    prompt = build_prompt(1, pf, plan_file, tmp_path, skip_precheck="1", is_first=True)
    assert "solve it yourself" in prompt.lower() or "autonomous" in prompt.lower() or "self-diagnose" in prompt.lower()

def test_prompt_instructs_patterns_consolidation(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    prompt = build_prompt(1, pf, plan_file, tmp_path, skip_precheck="1", is_first=True)
    assert "Codebase Patterns" in prompt or "codebase patterns" in prompt
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_stale_prompt_contains_error_context tests/ralph-loop/test_ralph_loop.py::test_reverted_items_in_prompt tests/ralph-loop/test_ralph_loop.py::test_normal_prompt_has_autonomous_instructions tests/ralph-loop/test_ralph_loop.py::test_prompt_instructs_patterns_consolidation -v`
Expected: FAIL

**Step 3: Write minimal implementation**

Modify `scripts/ralph_loop.py`:

1. Add import: `from scripts.lib.error_context import extract_error_context, format_reverted_context`
2. Modify `build_prompt()` signature to add `stale_rounds=0`, `log_path=None`, `reverted_items=None`.
3. Replace rules 8-9 with autonomous problem-solving instructions. Add stale-aware and reverted-aware sections. Add codebase patterns consolidation instruction.
4. Modify `main()`: store `reverted` from `revert_failed_checks()` in a variable that persists across iterations. Pass `stale_rounds=stale_rounds`, `log_path=log_file`, `reverted_items=last_reverted` to `build_prompt()` calls.

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/ -v`
Expected: ALL PASS (87 existing + 4 new)

**Step 5: Commit**
`feat: autonomous problem-solving prompt + error context injection + codebase patterns`

**Verify:** `python3 -m pytest tests/ralph-loop/ -v`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## Checklist

- [x] error_context.py extracts errors from log | `python3 -m pytest tests/ralph-loop/test_error_context.py -v`
- [x] build_prompt accepts stale_rounds/log_path/reverted_items params | `python3 -c "from scripts.ralph_loop import build_prompt; import inspect; sig=inspect.signature(build_prompt); assert 'stale_rounds' in sig.parameters and 'log_path' in sig.parameters and 'reverted_items' in sig.parameters"`
- [x] stale prompt contains error context and strategy-change instructions | `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_stale_prompt_contains_error_context -v`
- [x] reverted items appear in prompt | `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_reverted_items_in_prompt -v`
- [x] normal prompt has autonomous problem-solving instructions | `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_normal_prompt_has_autonomous_instructions -v`
- [x] prompt includes codebase patterns consolidation instruction | `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_prompt_instructs_patterns_consolidation -v`
- [x] main() passes stale_rounds, log_path, reverted to build_prompt | `python3 -c "import ast; tree=ast.parse(open('scripts/ralph_loop.py').read()); calls=[n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id=='build_prompt']; kws={kw.arg for c in calls for kw in c.keywords}; assert 'stale_rounds' in kws and 'log_path' in kws, f'missing kwargs in build_prompt calls: {kws}'"`
- [x] 回归测试通过 | `python3 -m pytest tests/ralph-loop/ -v`
