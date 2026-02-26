# Ralph Loop Multi-Instance Support

**Goal:** Enable multiple ralph loop instances to run concurrently in the same project, each targeting a different submodule worktree, with zero breaking changes to existing single-instance behavior. Include plan-level `Work Dir` declaration, automatic worktree setup in @execute flow, and hard boundary enforcement via hook.
**Non-Goals:** Batch orchestrator (ralph_multi.py) for launching multiple instances in one command. Changing plan.py or lock.py.
**Architecture:** Four layers: (1) `ralph_loop.py` — instance slug from plan name isolates lock/log/result; `RALPH_WORK_DIR` sets CLI subprocess cwd and prompt. (2) `commands/execute.md` — reads `Work Dir` from plan header, creates worktree if needed, sets env vars, launches ralph loop. (3) `hooks/gate/enforce-work-dir.sh` — PreToolUse hook that blocks fs_write outside `RALPH_WORK_DIR` when set. (4) Plan format — optional `**Work Dir:**` header field. When `Work Dir` is absent, all behavior is identical to today.
**Tech Stack:** Python 3, Bash, pytest

## Review
<!-- Reviewer writes here -->

## Tasks

### Task 1: Instance-Isolated Lock/Log/Result Files

**Files:**
- Modify: `scripts/ralph_loop.py`
- Test: `tests/ralph-loop/test_ralph_loop.py`

**Step 1: Write failing test**

Add test `test_multi_instance_file_isolation` that verifies:
- When `PLAN_POINTER_OVERRIDE` points to a plan named `foo-bar.md`, lock file is `.ralph-loop-foo-bar.lock`, log is `.ralph-loop-foo-bar.log`, result is `docs/plans/.ralph-result-foo-bar`
- When `PLAN_POINTER_OVERRIDE` is not set (default `.active`), files are `.ralph-loop.lock`, `.ralph-loop.log`, `docs/plans/.ralph-result` (backward compat)

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_multi_instance_file_isolation -v`
Expected: FAIL (no slug logic exists)

**Step 3: Write minimal implementation**

In `Config`, add `instance_slug: str = ""`. In `parse_config()`, derive slug from plan pointer:
- If plan_pointer is `docs/plans/.active` → slug = "" (default, no prefix)
- Otherwise → slug = plan pointer filename stem (e.g. `2026-02-26-sitebox-feat` from `docs/plans/2026-02-26-sitebox-feat.md`)

Add method `instance_path(base: str) -> Path` to Config:
- If slug is empty → return `Path(base)` (e.g. `.ralph-loop.lock`)
- If slug is set → inject slug (e.g. `.ralph-loop-{slug}.lock` for `.ralph-loop.lock`, `docs/plans/.ralph-result-{slug}` for `docs/plans/.ralph-result`)

In `main()`, replace hardcoded paths:
```python
log_file = cfg.instance_path(".ralph-loop.log")
lock = LockFile(cfg.instance_path(".ralph-loop.lock"))
summary_file = cfg.instance_path("docs/plans/.ralph-result")
```

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_multi_instance_file_isolation -v`
Expected: PASS

**Step 5: Commit**
`feat: instance-isolated lock/log/result files for multi ralph loop`

### Task 2: RALPH_WORK_DIR Support

**Files:**
- Modify: `scripts/ralph_loop.py`
- Modify: `scripts/lib/pty_runner.py`
- Test: `tests/ralph-loop/test_ralph_loop.py`

**Step 1: Write failing test**

Add test `test_work_dir_passed_to_subprocess` that verifies:
- When `RALPH_WORK_DIR` is set, `pty_run` receives `cwd` parameter
- The prompt includes a "Working directory:" line with the work_dir path

Add test `test_work_dir_unset_uses_project_root` that verifies:
- When `RALPH_WORK_DIR` is not set, behavior is unchanged (cwd = None, no Working directory in prompt)

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_work_dir_passed_to_subprocess -v`
Expected: FAIL

**Step 3: Write minimal implementation**

1. `Config`: add `work_dir: str = ""` field. `parse_config()`: read from `os.environ.get("RALPH_WORK_DIR", "")`.

2. `pty_runner.py`: add optional `cwd: str | None = None` param to `pty_run()`. Pass it to `subprocess.Popen(..., cwd=cwd)`.

3. `ralph_loop.py main()`: if `cfg.work_dir`, resolve it to absolute path. Pass `cwd=work_dir` to `pty_run()`. Also run dirty-tree check in that directory. Export `RALPH_WORK_DIR` to env so child CLI and hooks can read it: `os.environ["RALPH_WORK_DIR"] = str(work_dir_abs)`. Note: `_RALPH_LOOP_RUNNING` is already exported (line 245 of current code), so the hook will see both env vars.

4. `build_prompt()`: add optional `work_dir` param. When set, prepend to prompt:
   ```
   Working directory: {work_dir}
   You MUST work in this directory. All file edits, test runs, and git commits happen here.
   The plan file is in the parent project — read it but do NOT modify files outside your working directory.
   ```

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/ralph-loop/test_ralph_loop.py::test_work_dir_passed_to_subprocess -v`
Expected: PASS

**Step 5: Commit**
`feat: RALPH_WORK_DIR support for submodule worktree execution`

### Task 3: Work Dir Boundary Hook

**Files:**
- Create: `hooks/gate/enforce-work-dir.sh`
- Test: `tests/ralph-loop/test_ralph_loop.py` (or inline bash test)

**Step 1: Write failing test**

Test script that verifies:
- When `RALPH_WORK_DIR=/tmp/test-wt`, writing to `/tmp/test-wt/foo.py` → exit 0 (allowed)
- When `RALPH_WORK_DIR=/tmp/test-wt`, writing to `/tmp/other/bar.py` → exit 2 (blocked)
- When `RALPH_WORK_DIR` is unset, writing anywhere → exit 0 (no constraint, backward compat)
- When `_RALPH_LOOP_RUNNING` is unset (not in ralph loop), writing anywhere → exit 0 (hook only active during ralph loop execution)

**Step 2: Run test — verify it fails**
Expected: FAIL (hook doesn't exist)

**Step 3: Write minimal implementation**

Create `hooks/gate/enforce-work-dir.sh`:
```bash
#!/bin/bash
# enforce-work-dir.sh — PreToolUse[fs_write] gate
# When RALPH_WORK_DIR is set, block writes outside that directory.
source "$(dirname "$0")/../_lib/common.sh"

# Only active during ralph loop execution
[ "$_RALPH_LOOP_RUNNING" != "1" ] && exit 0

# No work_dir constraint → allow all
[ -z "$RALPH_WORK_DIR" ] && exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$TOOL_NAME" in
  fs_write|Write|Edit) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Resolve to absolute using realpath (follows symlinks, prevents symlink bypass)
# Use Python with proper argument passing to prevent command injection
RESOLVED=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE" 2>/dev/null)
[ -z "$RESOLVED" ] && hook_block "🚫 BLOCKED: Cannot resolve path: $FILE"

WORK_DIR_ABS=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$RALPH_WORK_DIR" 2>/dev/null)
[ -z "$WORK_DIR_ABS" ] && hook_block "🚫 BLOCKED: Cannot resolve RALPH_WORK_DIR"

# Allow writes inside work_dir
case "$RESOLVED" in
  "$WORK_DIR_ABS"/*) exit 0 ;;
  "$WORK_DIR_ABS") exit 0 ;;
esac

# Allow writes to the active plan file only (not entire plans dir)
PLAN_POINTER="${PLAN_POINTER_OVERRIDE:-docs/plans/.active}"
if [ -f "$PLAN_POINTER" ]; then
  ACTIVE_PLAN=$(cat "$PLAN_POINTER" | tr -d '[:space:]')
  ACTIVE_PLAN_ABS=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$ACTIVE_PLAN" 2>/dev/null)
  ACTIVE_PROGRESS="${ACTIVE_PLAN_ABS%.md}.progress.md"
  ACTIVE_FINDINGS="${ACTIVE_PLAN_ABS%.md}.findings.md"
  case "$RESOLVED" in
    "$ACTIVE_PLAN_ABS"|"$ACTIVE_PROGRESS"|"$ACTIVE_FINDINGS") exit 0 ;;
  esac
fi

hook_block "🚫 BLOCKED: Write outside work directory ($RESOLVED). Allowed: $WORK_DIR_ABS/*"
```

Register in hook config (`.kiro/agents/pilot.json` or equivalent).

**Step 4: Run test — verify it passes**
Expected: PASS

**Step 5: Commit**
`feat: enforce-work-dir hook blocks writes outside RALPH_WORK_DIR`

### Task 4: Plan Format + @execute Flow

**Files:**
- Modify: `commands/execute.md`
- Modify: `hooks/feedback/context-enrichment.sh`

**Step 1: Write failing test**

Test that context-enrichment detects `@execute` and when plan has `Work Dir`, the injected message includes `RALPH_WORK_DIR`.

**Step 2: Run test — verify it fails**
Expected: FAIL

**Step 3: Write minimal implementation**

1. Update `commands/execute.md` Step 1 to add after plan resolution:

   ```markdown
   ### Step 1b: Detect Work Dir

   Check if the plan header contains `**Work Dir:**`:
   ```bash
   WORK_DIR=$(grep -oP '^\*\*Work Dir:\*\*\s*\K.+' "$PLAN_FILE" | tr -d '[:space:]')
   ```

   If Work Dir is set:
   1. Resolve to absolute path relative to project root
   2. If path doesn't exist, create worktree:
      - Infer submodule from path (e.g. `../sitebox-feat` → `sitebox` submodule)
      - Infer branch from plan slug
      - `cd <submodule> && git worktree add <work_dir_abs> -b <branch>`
   3. Set environment variables for ralph loop launch:
      ```bash
      PLAN_POINTER_OVERRIDE=<plan_file_path> \
      RALPH_WORK_DIR=<work_dir_abs> \
      python3 scripts/ralph_loop.py
      ```
   ```

2. Update `hooks/feedback/context-enrichment.sh` @execute block to read Work Dir from plan and include it in the injected message:

   ```bash
   if echo "$USER_MSG" | grep -qE '^@execute|^/execute'; then
     PLAN_POINTER="docs/plans/.active"
     [ -f "$PLAN_POINTER" ] && PLAN_FILE=$(cat "$PLAN_POINTER" | tr -d '[:space:]')
     WORK_DIR=""
     if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
       WORK_DIR=$(grep -oP '^\*\*Work Dir:\*\*\s*\K.+' "$PLAN_FILE" 2>/dev/null | tr -d '[:space:]')
     fi
     if [ -n "$WORK_DIR" ]; then
       emit "🚀 Execute detected → Plan has Work Dir: $WORK_DIR. Create worktree if needed, then run: PLAN_POINTER_OVERRIDE=$PLAN_FILE RALPH_WORK_DIR=$WORK_DIR python3 scripts/ralph_loop.py"
     else
       emit "🚀 Execute detected → Run \`python3 scripts/ralph_loop.py\` immediately. Do NOT read the plan or implement tasks yourself."
     fi
   fi
   ```

**Step 4: Run test — verify it passes**
Expected: PASS

**Step 5: Commit**
`feat: @execute reads Work Dir from plan and sets up worktree`

### Task 5: Hook Registration

**Files:**
- Modify: `.kiro/agents/pilot.json` (or equivalent hook config)

**Step 1: Register enforce-work-dir.sh**

Add to preToolUse hooks for fs_write matcher:
```json
{
  "matcher": "fs_write",
  "command": "hooks/gate/enforce-work-dir.sh"
}
```

**Step 2: Verify**
Run: `jq '.hooks' .kiro/agents/pilot.json | grep -q 'enforce-work-dir'`

**Step 3: Commit**
`feat: register enforce-work-dir hook in pilot config`

### Task 6: Regression Tests

**Files:**
- Test: `tests/ralph-loop/`

**Step 1: Run full regression**
Run: `python3 -m pytest tests/ralph-loop/ -v`
Expected: ALL PASS

**Step 2: Commit (if any fixes needed)**
`fix: regression fixes for multi-instance support`

## Checklist

- [ ] slug derived from plan pointer filename | `python3 -c "from scripts.ralph_loop import parse_config; import os; os.environ['PLAN_POINTER_OVERRIDE']='docs/plans/2026-02-26-sitebox-feat.md'; c=parse_config(); assert c.instance_slug=='2026-02-26-sitebox-feat', c.instance_slug; print('OK')"`
- [ ] default plan pointer produces empty slug | `python3 -c "from scripts.ralph_loop import parse_config; c=parse_config(); assert c.instance_slug=='', c.instance_slug; print('OK')"`
- [ ] instance_path isolates lock file | `python3 -c "from scripts.ralph_loop import parse_config; import os; os.environ['PLAN_POINTER_OVERRIDE']='docs/plans/foo.md'; c=parse_config(); assert str(c.instance_path('.ralph-loop.lock'))=='.ralph-loop-foo.lock', str(c.instance_path('.ralph-loop.lock')); print('OK')"`
- [ ] instance_path returns default when no slug | `python3 -c "from scripts.ralph_loop import parse_config; import os; os.environ.pop('PLAN_POINTER_OVERRIDE',None); c=parse_config(); assert str(c.instance_path('.ralph-loop.lock'))=='.ralph-loop.lock'; print('OK')"`
- [ ] RALPH_WORK_DIR parsed into config | `python3 -c "from scripts.ralph_loop import parse_config; import os; os.environ['RALPH_WORK_DIR']='/tmp/wt'; c=parse_config(); assert c.work_dir=='/tmp/wt'; print('OK')"`
- [ ] pty_run accepts cwd param | `python3 -c "import inspect; from scripts.lib.pty_runner import pty_run; sig=inspect.signature(pty_run); assert 'cwd' in sig.parameters; print('OK')"`
- [ ] prompt includes work_dir when set | `python3 -c "from scripts.ralph_loop import build_prompt; from scripts.lib.plan import PlanFile; from pathlib import Path; Path('/tmp/_test_plan.md').write_text('## Checklist\n- [ ] test'); p=PlanFile(Path('/tmp/_test_plan.md')); s=build_prompt(1,p,Path('/tmp/_test_plan.md'),Path('.'),work_dir='/tmp/wt'); assert 'Working directory: /tmp/wt' in s; print('OK')"`
- [ ] prompt has no work_dir line when unset | `python3 -c "from scripts.ralph_loop import build_prompt; from scripts.lib.plan import PlanFile; from pathlib import Path; import inspect; sig=inspect.signature(build_prompt); assert 'work_dir' in sig.parameters, 'work_dir param missing'; Path('/tmp/_test_plan.md').write_text('## Checklist\n- [ ] test'); p=PlanFile(Path('/tmp/_test_plan.md')); s=build_prompt(1,p,Path('/tmp/_test_plan.md'),Path('.'),work_dir=''); assert 'Working directory' not in s; print('OK')"`
- [ ] hook blocks write outside work_dir | `RALPH_WORK_DIR=/tmp/test-wt _RALPH_LOOP_RUNNING=1 echo '{"tool_name":"fs_write","tool_input":{"file_path":"/tmp/other/evil.py"}}' | bash hooks/gate/enforce-work-dir.sh 2>&1; test $? -eq 2`
- [ ] hook allows write inside work_dir | `RALPH_WORK_DIR=/tmp/test-wt _RALPH_LOOP_RUNNING=1 echo '{"tool_name":"fs_write","tool_input":{"file_path":"/tmp/test-wt/good.py"}}' | bash hooks/gate/enforce-work-dir.sh 2>&1; test $? -eq 0`
- [ ] hook inactive when RALPH_WORK_DIR unset | `echo '{"tool_name":"fs_write","tool_input":{"file_path":"/tmp/anywhere.py"}}' | bash hooks/gate/enforce-work-dir.sh 2>&1; test $? -eq 0`
- [ ] hook inactive outside ralph loop | `RALPH_WORK_DIR=/tmp/test-wt echo '{"tool_name":"fs_write","tool_input":{"file_path":"/tmp/other/evil.py"}}' | bash hooks/gate/enforce-work-dir.sh 2>&1; test $? -eq 0`
- [ ] context-enrichment emits work_dir for @execute | `echo '{"prompt":"@execute"}' | PLAN_FILE_FOR_TEST=1 bash hooks/feedback/context-enrichment.sh 2>/dev/null | grep -q 'RALPH_WORK_DIR\|ralph_loop'`
- [ ] execute.md documents Work Dir flow | `grep -q 'Work Dir' commands/execute.md`
- [ ] enforce-work-dir.sh registered in hook config | `cat .kiro/agents/pilot.json | grep -q 'enforce-work-dir'`
- [ ] 回归测试通过 | `python3 -m pytest tests/ralph-loop/ -v`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|
