#!/bin/bash
# Tests for tools/validate-project.sh
# Run: bash tests/test-validate-project.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/../tools/validate-project.sh"
PASS=0
FAIL=0

# ─── Test helpers ─────────────────────────────────────────────────────────────

setup() {
  TMP=$(mktemp -d)
  # Minimal valid project structure
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

run_validate() {
  # Returns exit code via $?; capture stdout+stderr together
  bash "$VALIDATE" "$TMP" 2>&1 || true
}

run_validate_rc() {
  bash "$VALIDATE" "$TMP" >/dev/null 2>&1
  echo $?
}

# ─── Test: No overlay → passes ────────────────────────────────────────────────
echo "--- T01: No overlay file → exit 0"
setup
OUT=$(run_validate)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "no overlay passes" 0 "$RC"
teardown

# ─── Test E1: Invalid JSON overlay → exit 1 ───────────────────────────────────
echo "--- T02: E1 invalid JSON overlay → exit 1"
setup
echo "{not valid json" > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E1 invalid JSON exits 1" 1 "$RC"
assert_output_contains "E1 error message" "E1" "$OUT"
teardown

# ─── Test E1: Empty JSON overlay → exit 1 (jq treats {} as valid, empty string not) ──
echo "--- T03: E1 empty overlay file → exit 1"
setup
touch "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E1 empty file exits 1" 1 "$RC"
teardown

# ─── Test E2: extra_skills path missing SKILL.md → exit 1 ────────────────────
echo "--- T04: E2 extra_skills missing SKILL.md → exit 1"
setup
mkdir -p "$TMP/skills/myskill"
# No SKILL.md inside
echo '{"extra_skills": ["skills/myskill"]}' > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E2 missing SKILL.md exits 1" 1 "$RC"
assert_output_contains "E2 error message" "E2" "$OUT"
teardown

# ─── Test E2: extra_skills path has SKILL.md → passes ────────────────────────
echo "--- T05: E2 extra_skills with SKILL.md → exit 0"
setup
mkdir -p "$TMP/skills/myskill"
printf -- "---\nname: myskill\n---\n# MySkill" > "$TMP/skills/myskill/SKILL.md"
echo '{"extra_skills": ["skills/myskill"]}' > "$TMP/.omk-overlay.json"
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E2 valid SKILL.md exits 0" 0 "$RC"
teardown

# ─── Test E3: extra_hooks command not executable → exit 1 ────────────────────
echo "--- T06: E3 extra_hooks command not executable → exit 1"
setup
mkdir -p "$TMP/hooks"
touch "$TMP/hooks/my-hook.sh"
# Not chmod +x
echo '{"extra_hooks": {"postToolUse": [{"command": "hooks/my-hook.sh"}]}}' > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E3 non-exec hook exits 1" 1 "$RC"
assert_output_contains "E3 error message" "E3" "$OUT"
teardown

# ─── Test E3: extra_hooks command executable → passes ────────────────────────
echo "--- T07: E3 extra_hooks executable command → exit 0"
setup
mkdir -p "$TMP/hooks"
printf '#!/bin/bash\nexit 0\n' > "$TMP/hooks/my-hook.sh"
chmod +x "$TMP/hooks/my-hook.sh"
echo '{"extra_hooks": {"postToolUse": [{"command": "hooks/my-hook.sh"}]}}' > "$TMP/.omk-overlay.json"
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E3 exec hook exits 0" 0 "$RC"
teardown

# ─── Test E4: extra_hooks invalid event name → exit 1 ────────────────────────
echo "--- T08: E4 invalid event name → exit 1"
setup
mkdir -p "$TMP/hooks"
printf '#!/bin/bash\nexit 0\n' > "$TMP/hooks/my-hook.sh"
chmod +x "$TMP/hooks/my-hook.sh"
echo '{"extra_hooks": {"InvalidEvent": ["hooks/my-hook.sh"]}}' > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E4 invalid event exits 1" 1 "$RC"
assert_output_contains "E4 error message" "E4" "$OUT"
teardown

# ─── Test E8: knowledge/INDEX.md missing → exit 1 ────────────────────────────
echo "--- T09: E8 knowledge/INDEX.md missing → exit 1"
setup
rm "$TMP/knowledge/INDEX.md"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E8 missing INDEX.md exits 1" 1 "$RC"
assert_output_contains "E8 error message" "E8" "$OUT"
teardown

# ─── Test E8: knowledge/INDEX.md empty → exit 1 ──────────────────────────────
echo "--- T10: E8 knowledge/INDEX.md empty → exit 1"
setup
> "$TMP/knowledge/INDEX.md"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E8 empty INDEX.md exits 1" 1 "$RC"
assert_output_contains "E8 error message" "E8" "$OUT"
teardown

# ─── Test W1: SKILL.md missing frontmatter → warning, exit 0 ─────────────────
echo "--- T11: W1 SKILL.md missing frontmatter → warning exit 0"
setup
mkdir -p "$TMP/skills/myskill"
echo "# MySkill (no frontmatter)" > "$TMP/skills/myskill/SKILL.md"
echo '{"extra_skills": ["skills/myskill"]}' > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "W1 missing frontmatter exits 0" 0 "$RC"
assert_output_contains "W1 warning message" "W1" "$OUT"
teardown

# ─── Test E7: broken symlink → exit 1 ────────────────────────────────────────
echo "--- T12: E7 broken symlink → exit 1"
setup
mkdir -p "$TMP/.claude"
ln -s "/nonexistent/path/hooks" "$TMP/.claude/hooks"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E7 broken symlink exits 1" 1 "$RC"
assert_output_contains "E7 error message" "E7" "$OUT"
rm -f "$TMP/.claude/hooks"
teardown

# ─── Test E5: skill name conflicts framework skill → exit 1 ──────────────────
echo "--- T13: E5 skill name conflicts framework skill → exit 1"
setup
mkdir -p "$TMP/skills/planning"
printf -- "---\nname: planning\n---\n# Planning" > "$TMP/skills/planning/SKILL.md"
echo '{"extra_skills": ["skills/planning"]}' > "$TMP/.omk-overlay.json"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E5 skill conflict exits 1" 1 "$RC"
assert_output_contains "E5 error message" "E5" "$OUT"
teardown

# ─── Test W5: AGENTS.md >200 lines → warning, exit 0 ────────────────────────
echo "--- T14: W5 AGENTS.md >200 lines → warning exit 0"
setup
# Generate 201-line AGENTS.md with BEGIN/END markers
{
  echo "<!-- BEGIN OMK Identity -->"
  for i in $(seq 1 199); do echo "line $i"; done
  echo "<!-- END OMK Identity -->"
} > "$TMP/AGENTS.md"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "W5 long AGENTS.md exits 0" 0 "$RC"
assert_output_contains "W5 warning message" "W5" "$OUT"
teardown

# ─── Test E6: AGENTS.md missing markers → exit 1 ─────────────────────────────
echo "--- T15: E6 AGENTS.md missing BEGIN/END markers → exit 1"
setup
echo "# Just some content, no markers" > "$TMP/AGENTS.md"
OUT=$(bash "$VALIDATE" "$TMP" 2>&1 || true)
RC=$(bash "$VALIDATE" "$TMP" >/dev/null 2>&1; echo $?)
assert_exit "E6 missing markers exits 1" 1 "$RC"
assert_output_contains "E6 error message" "E6" "$OUT"
teardown

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
