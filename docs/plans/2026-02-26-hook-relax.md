# Hook Relax — Plan-Aware Protection Mode

**Goal:** Change hook system from plan-centric enforcement to plan-aware protection: allow all operations without a plan, allow non-plan-file operations with a plan, and make ralph loop dirty check a warning instead of a blocker.
**Non-Goals:** Changing security hooks (block-dangerous, block-secrets, etc.), modifying hook dispatch architecture, changing ralph loop execution logic beyond dirty check.
**Architecture:** Three targeted modifications to existing files — no new files, no new abstractions. enforce-ralph-loop.sh removes git commit interception and reorders bypass logic; pre-write.sh removes plan-requirement gate; ralph_loop.py softens dirty check.
**Tech Stack:** Bash, Python3

## Tasks

### Task 1: Relax enforce-ralph-loop.sh

**Files:**
- Modify: `hooks/gate/enforce-ralph-loop.sh`
- Test: `tests/hooks/test-ralph-gate.sh`

**Step 1: Write failing test**
Add test cases to `tests/hooks/test-ralph-gate.sh`:
- git commit with `.active` staged differently from HEAD should PASS (was blocked)
- git commit of non-plan files while plan is active should PASS

**Step 2: Run test — verify it fails**
Run: `bash tests/hooks/test-ralph-gate.sh`
Expected: FAIL (current hook blocks these)

**Step 3: Write minimal implementation**
In `enforce-ralph-loop.sh`:
1. Delete the entire git commit `.active` staged guard block (lines 18-35)
2. Move `_RALPH_LOOP_RUNNING` bypass to right after emergency bypass (before plan file checks)
3. In bash mode: remove any git commit interception — let all git commits through (protected file writes are already guarded by the denylist)

**Step 4: Run test — verify it passes**
Run: `bash tests/hooks/test-ralph-gate.sh`
Expected: PASS

**Step 5: Commit**
`feat: relax enforce-ralph-loop — remove git commit interception`

**Verify:** `bash tests/hooks/test-ralph-gate.sh`

### Task 2: Remove plan-requirement gate from pre-write.sh

**Files:**
- Modify: `hooks/gate/pre-write.sh`
- Test: `tests/hooks/test-pre-write-relax.sh`

**Step 1: Write failing test**
Create test that verifies: creating a new source file (.py) without any active plan should exit 0.

**Step 2: Run test — verify it fails**
Run: `bash tests/hooks/test-pre-write-relax.sh`
Expected: FAIL (current gate_check blocks)

**Step 3: Write minimal implementation**
In `pre-write.sh`, replace `gate_check()` function body:
- Remove the `find_active_plan` → block logic
- Remove the review verdict check
- Keep only the progress advisory (unchecked count display)

**Step 4: Run test — verify it passes**
Run: `bash tests/hooks/test-pre-write-relax.sh`
Expected: PASS

**Step 5: Commit**
`feat: remove plan-requirement gate from pre-write`

**Verify:** `bash tests/hooks/test-pre-write-relax.sh`

### Task 3: Soften ralph_loop.py dirty check

**Files:**
- Modify: `scripts/ralph_loop.py`
- Test: `tests/ralph-loop/test_dirty_check.py`

**Step 1: Write failing test**
Test that `main()` prints a warning but does NOT call `sys.exit` when working tree is dirty and `RALPH_SKIP_DIRTY_CHECK` is not set.

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_dirty_check.py -v`
Expected: FAIL

**Step 3: Write minimal implementation**
In `ralph_loop.py` `main()`, change the dirty check block:
```python
if not skip_dirty_check:
    r = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
    if r.stdout.strip():
        print(f"⚠️ Dirty working tree detected. Proceeding anyway (use RALPH_SKIP_DIRTY_CHECK=1 to silence).")
```

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/test_dirty_check.py -v`
Expected: PASS

**Step 5: Commit**
`feat: soften ralph-loop dirty check to warning`

**Verify:** `python3 -m pytest tests/ralph-loop/test_dirty_check.py -v`

### Task 4: Regression — existing tests still pass

**Files:**
- Test: `tests/hooks/test-ralph-gate.sh`
- Test: `tests/ralph-loop/`

**Step 1: Run all existing hook tests**
Run: `bash tests/hooks/test-ralph-gate.sh && bash tests/hooks/test-cc-compat.sh && bash tests/hooks/test-kiro-compat.sh`

**Step 2: Run all ralph-loop tests**
Run: `python3 -m pytest tests/ralph-loop/ -v`

**Step 3: Fix any regressions**

**Step 4: Commit if fixes needed**

**Verify:** `bash tests/hooks/test-ralph-gate.sh && python3 -m pytest tests/ralph-loop/ -v`

## Checklist

- [x] enforce-ralph-loop.sh 不再因 .active staged 拦截 git commit | `cd /tmp && git init _test_hook && cd _test_hook && git commit --allow-empty -m init && mkdir -p docs/plans && echo x > docs/plans/.active && git add docs/plans/.active && git commit -m base && echo y > docs/plans/.active && git add docs/plans/.active && echo '{"tool_name":"execute_bash","tool_input":{"command":"git commit -m test"}}' | bash /Users/wanshao/project/oh-my-claude-code-wt-hook-relax/hooks/gate/enforce-ralph-loop.sh 2>&1; rc=$?; cd /; test $rc -eq 0`
- [ ] 无 plan 时创建 source 文件不被 block | `rm -f docs/plans/.active; WORKFLOW_PLAN_WINDOW=0 bash -c 'echo "{\"tool_name\":\"fs_write\",\"tool_input\":{\"command\":\"create\",\"file_path\":\"test_new.py\",\"content\":\"x=1\"}}" | bash hooks/gate/pre-write.sh 2>&1'; test $? -eq 0`
- [ ] 有 plan 时创建非 plan 文件不被 block | `echo "docs/plans/2026-02-26-hook-relax.md" > docs/plans/.active; echo '{"tool_name":"fs_write","tool_input":{"command":"create","file_path":"unrelated.py","content":"x=1"}}' | bash hooks/gate/pre-write.sh 2>&1; rc=$?; rm -f docs/plans/.active; test $rc -eq 0`
- [ ] ralph loop dirty check 不再 die | `grep -q 'die.*Dirty' scripts/ralph_loop.py; test $? -ne 0`
- [ ] 回归测试通过 | `python3 -m pytest tests/ralph-loop/ -v`
- [ ] hook 测试通过 | `bash tests/hooks/test-ralph-gate.sh`

## Review

**Round 1:** 4 reviewers (Goal Alignment, Verify Correctness, Completeness, Compatibility & Rollback)
- Goal Alignment: APPROVE
- Verify Correctness: REQUEST CHANGES — checklist #1/#2/#3 unsound
- Completeness: REQUEST CHANGES — bypass relocation coverage (addressed by Task 1 tests)
- Compatibility & Rollback: REQUEST CHANGES — regression timing (addressed by TDD verify steps)

**Round 2:** 2 reviewers (fixed angles only)
- Goal Alignment: APPROVE
- Verify Correctness: REQUEST CHANGES — checklist #1 still unsound (fixed: added .active staged scenario)

**Final Verdict: APPROVE** (all substantive issues resolved)

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|
