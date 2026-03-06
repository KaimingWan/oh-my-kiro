#!/bin/bash
# post-write.sh — Merged postToolUse[fs_write] dispatcher (Kiro + CC)
# Combines: auto-lint + auto-test + remind-update-progress
# Each function is independent — one failure doesn't block others.
source "$(dirname "$0")/../_lib/common.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
  fs_write|Write|Edit) FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) ;;
  *) exit 0 ;;
esac
[ -z "$FILE" ] && exit 0

# === Lint (silent on failure) ===
run_lint() {
  case "$FILE" in
    *.ts|*.tsx|*.js|*.jsx)
      command -v npx &>/dev/null && [ -f "node_modules/.bin/eslint" ] && npx eslint --fix "$FILE" 2>/dev/null ;;
    *.py)
      if command -v ruff &>/dev/null; then ruff check --fix "$FILE" 2>/dev/null
      elif command -v black &>/dev/null; then black -q "$FILE" 2>/dev/null; fi ;;
    *.rs) command -v rustfmt &>/dev/null && rustfmt "$FILE" 2>/dev/null ;;
    *.go) command -v gofmt &>/dev/null && gofmt -w "$FILE" 2>/dev/null ;;
  esac
  return 0
}

# === Test (exit 1 on failure) ===
run_test() {
  is_source_file "$FILE" || return 0

  # Debounce: skip if same file tested within 30s
  LOCK="/tmp/auto-test-$(echo "$FILE" | shasum 2>/dev/null | cut -c1-8 || echo "default").lock"
  if [ -f "$LOCK" ]; then
    LOCK_AGE=$(( $(date +%s) - $(file_mtime "$LOCK") ))
    [ "$LOCK_AGE" -lt 30 ] && return 0
  fi
  touch "$LOCK"

  TEST_CMD=$(detect_test_command)
  if [ -n "$TEST_CMD" ]; then
    # Strip trailing redirect noise; stderr captured via 2>&1 in the subshell below.
    # Word-split is intentional: TEST_CMD is an internally-generated, safe command string.
    _clean_cmd="${TEST_CMD% 2>&1}"
    read -ra _cmd <<< "$_clean_cmd"
    TEST_OUTPUT=$("${_cmd[@]}" 2>&1)
    if [ $? -ne 0 ]; then
      echo "⚠️ Tests failed after editing $FILE (last 3 lines):" >&2
      echo "$TEST_OUTPUT" | tail -3 >&2
      return 1
    fi
  fi
  return 0
}


# === OV index (knowledge files) ===
run_ov_index() {
  case "$FILE" in
    knowledge/*.md|*.findings.md|*.progress.md)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      OV_LIB="$SCRIPT_DIR/../_lib/ov-init.sh"
      if [ -f "$OV_LIB" ]; then
        source "$OV_LIB"
        if ov_init 2>/dev/null; then
          ov_add "$FILE" "knowledge update" >/dev/null 2>&1
        fi
      fi
      ;;
  esac
  return 0
}

# === Lesson scenario generation (lessons-learned.md) ===
run_lesson_scenarios() {
  case "$FILE" in
    *lessons-learned.md) ;;
    *) return 0 ;;
  esac
  local GEN_SCRIPT
  # Check OMK scripts dir first, then project tools/
  for candidate in "$(dirname "${BASH_SOURCE[0]}")/../../scripts/generate-lesson-scenarios.py" "tools/generate-lesson-scenarios.py"; do
    [ -f "$candidate" ] && GEN_SCRIPT="$candidate" && break
  done
  [ -z "$GEN_SCRIPT" ] && return 0

  local NEW_CONTENT
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_str // .tool_input.file_text // empty' 2>/dev/null)
  [ -z "$NEW_CONTENT" ] && return 0
  local SUMMARY
  SUMMARY=$(echo "$NEW_CONTENT" | head -5 | tr '\n' ' ' | cut -c1-200)
  [ -z "$SUMMARY" ] && return 0

  if [ -S "${OV_SOCKET:-/tmp/omk-ov.sock}" ]; then
    python3 "$GEN_SCRIPT" --single "$SUMMARY" 2>/dev/null &
  else
    python3 "$GEN_SCRIPT" --single "$SUMMARY" --dry-run 2>/dev/null &
  fi
  echo "📝 Lesson detected → scenario generation triggered" >&2
  return 0
}

# --- Execute all ---
run_lint || true
run_test
run_ov_index || true
run_lesson_scenarios || true
exit $?
