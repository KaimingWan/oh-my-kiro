# Reasoning Loop & Coarse Checklist Support

**Goal:** Enhance ralph loop prompt with a reasoning loop (observe-think-plan-execute-reflect-correct) so the agent can autonomously handle coarse/vague checklist items, and update the planning skill to teach plan writers how to write coarse items with appropriate verify commands.
**Non-Goals:** Rewriting ralph loop outer architecture. Removing verify command requirement from hooks. Adding new Python modules. Changing hook enforcement logic.
**Architecture:** Pure prompt engineering — inject reasoning loop instructions into build_prompt() and add coarse-item guidance to skills/planning/SKILL.md. No new files, no architecture changes.
**Tech Stack:** Python (ralph_loop.py), Markdown (SKILL.md)
**Work Dir:** `.`

## Tasks

### Task 1: Add reasoning loop instructions to build_prompt

**Files:**
- Modify: `scripts/ralph_loop.py`
- Test: `tests/ralph-loop/test_ralph_loop.py`

**Step 1: Write failing test**

Add test that verifies reasoning loop keywords and structure appear in prompt output:

```python
def test_reasoning_loop_in_prompt(tmp_path):
    plan = tmp_path / "plan.md"
    plan.write_text("- [ ] Implement user auth module | `python3 -c 'import auth'`\n")
    from scripts.ralph_loop import build_prompt
    from scripts.lib.plan import PlanFile
    result = build_prompt(1, PlanFile(plan), plan, tmp_path)
    # Verify all 7 reasoning loop steps are present
    for step in ["OBSERVE", "THINK", "PLAN", "EXECUTE", "REFLECT", "CORRECT", "VERIFY"]:
        assert step in result, f"Missing reasoning loop step: {step}"
    # Verify the section header exists
    assert "Reasoning Loop" in result
    # Verify it mentions coarse/vague items
    assert "coarse" in result.lower() or "vague" in result.lower()
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_reasoning_loop_in_prompt -v`
Expected: FAIL (keywords not in current prompt)

**Step 3: Write minimal implementation**

Add a reasoning loop section to the prompt string in build_prompt(), inserted after the existing Rules block. The section teaches the agent to handle coarse items via an internal reasoning cycle with steps: OBSERVE, THINK, PLAN, EXECUTE, REFLECT, CORRECT, VERIFY. The agent should decompose vague items into concrete sub-steps, execute them iteratively, and only mark done when the verify command passes.

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_reasoning_loop_in_prompt -v`
Expected: PASS

**Step 5: Commit**

**Verify:**
`python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_reasoning_loop_in_prompt -v`

### Task 2: Add coarse-item guidance to planning skill

**Files:**
- Modify: `skills/planning/SKILL.md`

**Step 1: Implementation**

Add a "Coarse Checklist Items" subsection under the existing "Checklist Format" section in SKILL.md. This teaches plan writers that checklist items can be high-level as long as the verify command is meaningful. Include examples of fine-grained vs coarse items, and rules: verify must still be executable and exit 0, use module-level or integration-level test commands, the executing agent will autonomously decompose using the Reasoning Loop.

**Step 2: Verify**

Verify the content was added correctly.

**Verify:**
`grep -q 'Coarse Checklist Items' skills/planning/SKILL.md`

### Task 3: Regression test

**Files:**
- Test: `tests/ralph-loop/test_ralph_loop.py`

Run full regression to ensure nothing broke.

**Verify:**
`python3 -m pytest tests/ralph-loop/ -v -k 'not test_flock_prevents_double_ralph'`

## Checklist

- [x] Reasoning loop instructions added to build_prompt | `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_reasoning_loop_in_prompt -v`
- [ ] Coarse-item guidance added to planning skill | `grep -q 'Coarse Checklist Items' skills/planning/SKILL.md`
- [ ] 回归测试通过 | `python3 -m pytest tests/ralph-loop/ -v -k 'not test_flock_prevents_double_ralph'`

## Review
<!-- Reviewer writes here -->

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## Findings
