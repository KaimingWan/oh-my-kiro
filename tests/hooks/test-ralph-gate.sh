#!/bin/bash
# test-ralph-gate.sh — Tests for enforce-ralph-loop.sh denylist mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

# Ensure clean environment — tests may run inside a ralph loop
unset _RALPH_LOOP_RUNNING 2>/dev/null || true

PASS=0
FAIL=0

HOOK="hooks/gate/enforce-ralph-loop.sh"

run_test() {
  local name="$1" expected_exit="$2"
  shift 2
  local input
  input=$(cat)
  local actual_exit=0
  echo "$input" | bash "$HOOK" >/dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create a temporary plan and activate it ---
TMPDIR_TEST=$(mktemp -d)
ORIG_ACTIVE=""
[ -f "docs/plans/.active" ] && ORIG_ACTIVE=$(cat "docs/plans/.active")
ORIG_LOCK=""
[ -f ".ralph-loop.lock" ] && ORIG_LOCK=$(cat ".ralph-loop.lock") && mv ".ralph-loop.lock" "$TMPDIR_TEST/.ralph-loop.lock.bak"

cleanup() {
  set +e  # Don't fail on cleanup errors
  # Restore lock file
  if [ -n "$ORIG_LOCK" ]; then
    echo "$ORIG_LOCK" > ".ralph-loop.lock"
  fi
  # Remove test artifacts
  [ -d "$TMPDIR_TEST" ] && command rm -rf "$TMPDIR_TEST"
  # Restore .active
  if [ -n "$ORIG_ACTIVE" ]; then
    echo "$ORIG_ACTIVE" > "docs/plans/.active"
  else
    : > "docs/plans/.active"
  fi
  command rm -f "docs/plans/.test-ralph-plan.md" 2>/dev/null
  command rm -f ".skip-ralph" 2>/dev/null
}
trap cleanup EXIT

# Create a test plan with unchecked items and protected files
TEST_PLAN="docs/plans/.test-ralph-plan.md"
cat > "$TEST_PLAN" << 'PLANEOF'
# Test Plan

## Files:
- Modify: `hooks/gate/enforce-ralph-loop.sh`
- Modify: `hooks/security/block-dangerous.sh`
- Create: `tests/hooks/test-ralph-gate.sh`

## Checklist
- [ ] do something | `echo ok`
PLANEOF

# Activate the test plan
echo "$TEST_PLAN" > docs/plans/.active

# --- Test group 1: No active plan (should allow all) ---
PREV_ACTIVE="$TEST_PLAN"
echo "" > docs/plans/.active  # empty .active = no active plan

run_test "ALLOW when no active plan (bash)" 0 <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"echo hello"}}
EOF

echo "$PREV_ACTIVE" > docs/plans/.active

# --- Test group 2: Active plan present, no ralph-loop lock ---

# Test: unknown tool passthrough
run_test "ALLOW unknown tool (Read)" 0 <<'EOF'
{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}
EOF

# Test: write to NON-protected file is ALLOWED (denylist mode)
run_test "ALLOW write to non-protected file" 0 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/docs/plans/some-new-plan.md"}}
EOF

# Test: write to protected file is BLOCKED
run_test "BLOCK write to protected file (Modify)" 2 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/hooks/gate/enforce-ralph-loop.sh"}}
EOF

# Test: edit to protected file is BLOCKED
run_test "BLOCK edit to protected file" 2 <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$PROJECT_DIR/hooks/security/block-dangerous.sh","old_string":"x","new_string":"y"}}
EOF

# Test: write to .active pointer is always blocked
run_test "BLOCK write to .active pointer" 2 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/docs/plans/.active"}}
EOF

# Test: path traversal is blocked
run_test "BLOCK path traversal" 2 <<'EOF'
{"tool_name":"Write","tool_input":{"file_path":"../etc/passwd"}}
EOF

# Test: lock file forgery blocked
run_test "BLOCK lock file forgery" 2 <<'EOF'
{"tool_name":"Write","tool_input":{"file_path":".ralph-loop.lock"}}
EOF

# Test: ralph_loop.py invocation is ALLOWED in bash mode
run_test "ALLOW ralph_loop.py bash invocation" 0 <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"python3 scripts/ralph_loop.py"}}
EOF

# Test: git status is ALLOWED in bash mode (denylist - no write)
run_test "ALLOW git status bash" 0 <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status"}}
EOF

# --- Test group 3: Emergency bypass (.skip-ralph) ---
touch .skip-ralph

run_test "ALLOW bash with .skip-ralph" 0 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/hooks/gate/enforce-ralph-loop.sh"}}
EOF

rm -f .skip-ralph

# --- Test group 4: Ralph-loop lock active ---
echo "$$" > .ralph-loop.lock

run_test "ALLOW write to protected file when lock active" 0 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/hooks/gate/enforce-ralph-loop.sh"}}
EOF

rm -f .ralph-loop.lock

# --- Test group 5: Env var bypass ---
export _RALPH_LOOP_RUNNING=1

run_test "ALLOW with _RALPH_LOOP_RUNNING=1" 0 <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$PROJECT_DIR/hooks/gate/enforce-ralph-loop.sh"}}
EOF

unset _RALPH_LOOP_RUNNING

# --- Summary ---
echo ""
echo "=== Ralph Gate Tests: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
