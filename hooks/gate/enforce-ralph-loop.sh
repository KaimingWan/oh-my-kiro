#!/bin/bash
# enforce-ralph-loop.sh — PreToolUse[execute_bash, fs_write] gate
# When an active plan has unchecked items, block direct execution.
# Agent must use ralph_loop.py, not execute tasks directly.
source "$(dirname "$0")/../_lib/common.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$TOOL_NAME" in
  execute_bash|Bash) MODE="bash" ;;
  fs_write|Write|Edit) MODE="write" ;;
  *) exit 0 ;;
esac

PLAN_POINTER="docs/plans/.active"
LOCK_FILE=".ralph-loop.lock"

# Emergency bypass
if [ -f ".skip-ralph" ]; then
  echo "⚠️ Ralph-loop check skipped (.skip-ralph exists)." >&2
  exit 0
fi

# Ralph-loop worker process bypass
if [ "$_RALPH_LOOP_RUNNING" = "1" ]; then
  exit 0
fi

# No active plan → allow
[ ! -f "$PLAN_POINTER" ] && exit 0

PLAN_FILE=$(cat "$PLAN_POINTER" | tr -d '[:space:]')
[ ! -f "$PLAN_FILE" ] && exit 0

# No unchecked items in last Checklist section → allow (plan is done)
# awk resets buffer on each ## Checklist, so only the last section survives
UNCHECKED=$(awk '/^## Checklist/{found=1;buf="";next} found && /^## /{found=0} found{buf=buf"\n"$0} END{print buf}' "$PLAN_FILE" 2>/dev/null | grep -c '^\- \[ \]' || true)
[ "${UNCHECKED:-0}" -eq 0 ] && exit 0

# Ralph-loop running (lock file exists AND process alive) → allow
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    # Intentional: allows ANY process (including executor subagents) when ralph-loop is alive.
    # kill -0 checks if ralph-loop PID exists, not if current process IS ralph-loop.
    exit 0
  fi
  # Stale lock — process dead, clean it up
  rm -f "$LOCK_FILE" 2>/dev/null
fi

# --- Active plan, unchecked items, no ralph-loop ---

block_msg() {
  echo "🚫 BLOCKED: Run python3 scripts/ralph_loop.py ($UNCHECKED items remaining${1:+, $1})" >&2
  exit 2
}

# Extract protected files from plan's "Files:" sections (lines starting with "- Modify:")
# These are the files the plan intends to change — direct edits outside ralph-loop are blocked.
extract_protected_files() {
  grep -E '^\-[[:space:]]+(Modify|Create):[[:space:]]+' "$PLAN_FILE" 2>/dev/null \
    | sed -E 's/^\-[[:space:]]+(Modify|Create):[[:space:]]+`?([^`]+)`?.*/\2/' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Check if a file path matches the protected list
is_protected_file() {
  local target="$1"
  local pf
  while IFS= read -r pf; do
    [ -z "$pf" ] && continue
    # Match exact path or basename
    if [ "$target" = "$pf" ] || [ "$(basename "$target")" = "$(basename "$pf")" ]; then
      return 0
    fi
  done < <(extract_protected_files)
  return 1
}

if [ "$MODE" = "bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

  # Strip leading "cd <path> &&" prefix (kiro-cli prepends this)
  CMD=$(echo "$CMD" | sed -E 's|^cd[[:space:]]+[^;&|]*&&[[:space:]]*||')

  # Allow ralph-loop invocations
  echo "$CMD" | grep -qE 'ralph[-_.]loop|ralph_loop' && exit 0

  # Brainstorm gate: block bash commands that create plan files without brainstorm confirmation
  if echo "$CMD" | grep -qE 'docs/plans/.*\.md' && [ ! -f ".brainstorm-confirmed" ] && [ ! -f ".skip-plan" ]; then
    if echo "$CMD" | grep -qE '(open|write|>|create)'; then
      block_msg "Creating plan via bash without brainstorm confirmation"
    fi
  fi

  # Block commands that delete/overwrite .active
  echo "$CMD" | grep -qE '(rm|>|>>|mv|cp).*\.active' && block_msg "Cannot manipulate .active file"

  # Denylist mode: block only if command writes to a protected file
  # Check for file redirection or write patterns targeting protected files
  if echo "$CMD" | grep -qE '(>|>>|tee|cp|mv|sed[[:space:]]+-i)'; then
    # Extract potential target file from the command
    TARGET_FILE=$(echo "$CMD" | grep -oE '>[[:space:]]*[^[:space:]|;&]+' | head -1 | sed 's/^>[[:space:]]*//')
    if [ -n "$TARGET_FILE" ] && is_protected_file "$TARGET_FILE"; then
      block_msg "Direct write to protected plan file '$TARGET_FILE'"
    fi
  fi

  # Allow all other bash commands by default (denylist mode)
  exit 0
fi

if [ "$MODE" = "write" ]; then
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

  # Normalize absolute path to relative (Kiro sends absolute paths, allowlist uses relative)
  WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  case "$FILE" in
    "$WORKSPACE"/*) FILE="${FILE#$WORKSPACE/}" ;;
  esac

  # Path traversal check
  echo "$FILE" | grep -q '\.\.' && block_msg "Path traversal (..) not allowed"

  # Block lock forgery
  case "$FILE" in
    *.ralph-loop.lock|*ralph-loop.lock) block_msg "Cannot write to lock file" ;;
  esac

  # Always block .active pointer manipulation
  case "$FILE" in
    docs/plans/.active) block_msg "Cannot write to .active pointer outside ralph-loop" ;;
  esac

  # Denylist mode: allow by default, only block writes to protected files
  if is_protected_file "$FILE"; then
    block_msg "Direct write to protected plan file '$FILE'"
  fi

  # Allow everything else (denylist mode — not in protected list)
  exit 0
fi
