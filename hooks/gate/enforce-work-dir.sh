#!/bin/bash
# enforce-work-dir.sh — PreToolUse gate
# When RALPH_WORK_DIR is set during ralph loop, block writes outside that directory.
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

RESOLVED=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE" 2>/dev/null)
[ -z "$RESOLVED" ] && hook_block "🚫 BLOCKED: Cannot resolve path: $FILE"

WORK_DIR_ABS=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$RALPH_WORK_DIR" 2>/dev/null)
[ -z "$WORK_DIR_ABS" ] && hook_block "🚫 BLOCKED: Cannot resolve RALPH_WORK_DIR"

# Allow writes inside work_dir
case "$RESOLVED" in
  "$WORK_DIR_ABS"/*|"$WORK_DIR_ABS") exit 0 ;;
esac

# Allow writes to active plan and its progress/findings files
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
