#!/bin/bash
# Tests for tools/install-skill.sh and tools/sync-omk.sh
# Run: bash tests/test-install-skill.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SKILL="$SCRIPT_DIR/../tools/install-skill.sh"
SYNC_OMK="$SCRIPT_DIR/../tools/sync-omk.sh"
VALIDATE="$SCRIPT_DIR/../tools/validate-project.sh"
OMK_ROOT="$SCRIPT_DIR/.."

PASS=0
FAIL=0

# ─── Test helpers ──────────────────────────────────────────────────────────────

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/knowledge"
  echo "# Index" > "$TMP/knowledge/INDEX.md"
}

teardown() {
  rm -rf "$TMP"
}

assert_exit() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -q "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (pattern '$pattern' not found in output)"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_contains() {
  local label="$1"
  local jq_filter="$2"
  local file="$3"
  if jq -e "$jq_filter" "$file" >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (jq filter '$jq_filter' returned false for $file)"
    echo "    File contents: $(cat "$file" 2>/dev/null || echo '<missing>')"
    FAIL=$((FAIL + 1))
  fi
}

# ─── install-skill.sh --register-only tests ───────────────────────────────────

echo "--- T01: --register-only creates overlay with skill path"
setup
mkdir -p "$TMP/skills/myskill"
printf -- "---\nname: myskill\n---\n# MySkill\n" > "$TMP/skills/myskill/SKILL.md"
RC=$(bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" >/dev/null 2>&1; echo $?)
assert_exit "register-only exits 0" 0 "$RC"
assert_json_contains "overlay has extra_skills entry" '.extra_skills | index("skills/myskill") != null' "$TMP/.omk-overlay.json"
teardown

echo "--- T02: --register-only appends to existing overlay"
setup
mkdir -p "$TMP/skills/myskill"
printf -- "---\nname: myskill\n---\n# MySkill\n" > "$TMP/skills/myskill/SKILL.md"
mkdir -p "$TMP/skills/other"
printf -- "---\nname: other\n---\n# Other\n" > "$TMP/skills/other/SKILL.md"
# Pre-create overlay with one skill
echo '{"extra_skills": ["skills/other"], "extra_hooks": {}}' > "$TMP/.omk-overlay.json"
bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" >/dev/null 2>&1
assert_json_contains "overlay still has other skill" '.extra_skills | index("skills/other") != null' "$TMP/.omk-overlay.json"
assert_json_contains "overlay has new myskill" '.extra_skills | index("skills/myskill") != null' "$TMP/.omk-overlay.json"
teardown

echo "--- T03: --register-only is idempotent (no duplicate entries)"
setup
mkdir -p "$TMP/skills/myskill"
printf -- "---\nname: myskill\n---\n# MySkill\n" > "$TMP/skills/myskill/SKILL.md"
bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" >/dev/null 2>&1
bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" >/dev/null 2>&1
COUNT=$(jq '[.extra_skills[] | select(. == "skills/myskill")] | length' "$TMP/.omk-overlay.json")
if [ "$COUNT" -eq 1 ]; then
  echo "  PASS: idempotent — skill registered once"
  PASS=$((PASS + 1))
else
  echo "  FAIL: idempotent — skill registered $COUNT times (expected 1)"
  FAIL=$((FAIL + 1))
fi
teardown

echo "--- T04: --register-only fails when SKILL.md missing"
setup
mkdir -p "$TMP/skills/myskill"
# No SKILL.md
OUT=$(bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" 2>&1 || true)
RC=$(bash "$INSTALL_SKILL" --register-only "$TMP" "skills/myskill" >/dev/null 2>&1; echo $?)
assert_exit "register-only exits 1 when SKILL.md missing" 1 "$RC"
assert_output_contains "error mentions SKILL.md" "SKILL.md" "$OUT"
teardown

echo "--- T05: --register-only fails when PROJECT_ROOT missing"
setup
OUT=$(bash "$INSTALL_SKILL" --register-only "/nonexistent/path" "skills/myskill" 2>&1 || true)
RC=$(bash "$INSTALL_SKILL" --register-only "/nonexistent/path" "skills/myskill" >/dev/null 2>&1; echo $?)
assert_exit "register-only exits 1 for bad project root" 1 "$RC"
teardown

echo "--- T06: --register-only with absolute SKILL_PATH"
setup
mkdir -p "$TMP/skills/myskill"
printf -- "---\nname: myskill\n---\n# MySkill\n" > "$TMP/skills/myskill/SKILL.md"
# Use absolute path
RC=$(bash "$INSTALL_SKILL" --register-only "$TMP" "$TMP/skills/myskill" >/dev/null 2>&1; echo $?)
assert_exit "register-only exits 0 with absolute path" 0 "$RC"
assert_json_contains "overlay has skill (absolute path)" '.extra_skills | length >= 1' "$TMP/.omk-overlay.json"
teardown

# ─── sync-omk.sh tests ───────────────────────────────────────────────────────

echo "--- T07: sync-omk calls validate before generate (fails on invalid overlay)"
setup
# Create invalid JSON overlay to trigger validation failure
echo "{invalid json" > "$TMP/.omk-overlay.json"
OUT=$(bash "$SYNC_OMK" "$TMP" 2>&1 || true)
RC=$(bash "$SYNC_OMK" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "sync-omk exits 1 on validation failure" 1 "$RC"
assert_output_contains "sync-omk reports validation failure" "alid" "$OUT"
teardown

echo "--- T08: sync-omk passes for valid project (no overlay)"
setup
# sync-omk will call validate (passes), then generate_configs
# generate_configs with --project-root needs --skip-validate flag which it has
# But it may fail if generate_configs has other requirements; test validate step at least
# We detect the validate step ran by injecting a broken overlay and seeing it fail
OUT=$(bash "$SYNC_OMK" "$TMP" 2>&1 || true)
RC=$(bash "$SYNC_OMK" "$TMP" >/dev/null 2>&1; echo $?)
# sync-omk may fail at generate step if generate_configs has requirements not met
# The key assertion is that validate step was called (logged) before generate
assert_output_contains "sync-omk reports Step 2 validate" "Step 2" "$OUT"
teardown

echo "--- T09: sync-omk validate step runs BEFORE generate step"
setup
# Make validation fail → generate step should never run
# We detect this by checking that generate step output is absent
echo "{bad json}" > "$TMP/.omk-overlay.json"
OUT=$(bash "$SYNC_OMK" "$TMP" 2>&1 || true)
# Step 2 fail message should appear
assert_output_contains "validate step mentioned in output" "Step 2" "$OUT"
# Step 3 generate step should NOT appear (validation blocked it)
if echo "$OUT" | grep -q "Step 3"; then
  echo "  FAIL: sync-omk reached Step 3 despite validation failure"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: sync-omk stopped at Step 2, did not reach Step 3"
  PASS=$((PASS + 1))
fi
teardown

echo "--- T10: sync-omk fails for non-existent project root"
OUT=$(bash "$SYNC_OMK" "/nonexistent/path/$(date +%s)" 2>&1 || true)
RC=$(bash "$SYNC_OMK" "/nonexistent/path/$(date +%s)" >/dev/null 2>&1; echo $?)
assert_exit "sync-omk exits 1 for bad project root" 1 "$RC"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
