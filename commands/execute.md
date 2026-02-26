Execute an approved plan with Ralph Loop hard constraint. Agent stops don't matter — bash loop keeps going until all checklist items are done.

## Step 1: Load Plan

Resolve which plan to execute:
1. Read `docs/plans/.active` — if it exists, use that path
2. If not found, find the most recently modified `docs/plans/*.md` and write it to `docs/plans/.active`
3. If multiple plans modified within the last hour, list them and ask the user to pick

Verify the plan has reviewer APPROVE verdict. If not approved, tell the user to run @plan first.

## Step 1b: Detect Work Dir

Check if the plan header contains `**Work Dir:**`:
```bash
WORK_DIR=$(grep -oE '^\*\*Work Dir:\*\*\s*.+' "$PLAN_FILE" | sed 's/^\*\*Work Dir:\*\*\s*//' | tr -d '[:space:]')
```

If Work Dir is set:
1. Resolve to absolute path relative to project root
2. If path doesn't exist, create worktree (infer submodule and branch from plan slug)
3. Launch ralph loop with isolation env vars:
```bash
PLAN_POINTER_OVERRIDE=<plan_file_path> RALPH_WORK_DIR=<work_dir_abs> python3 scripts/ralph_loop.py
```

If Work Dir is absent, proceed normally (backward compatible).

## Step 2: Verify Checklist

The plan MUST contain a `## Checklist` section with at least one `- [ ]` item. If missing, STOP and tell the user the plan needs a checklist.

## Step 3: Launch Ralph Loop

Run **foreground** (NEVER use `nohup &` — you need to see the exit summary):
```bash
python3 scripts/ralph_loop.py
```

This bash script will:
- Loop until all `- [ ]` items become `- [x]`
- Each iteration spawns a fresh Kiro CLI instance with clean context
- Circuit breaker: exits if 3 consecutive rounds make no progress
- Agent stopping is fine — the loop restarts a new instance
- On exit (success or failure), prints a full summary to stdout

## Step 4: Report Results

The script prints a summary block on exit. Use that output to report:
- How many checklist items completed vs total
- Any `- [SKIP]` items with reasons
- Read skills/finishing/SKILL.md for merge/PR/cleanup options
