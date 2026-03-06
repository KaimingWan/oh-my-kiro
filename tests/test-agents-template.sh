#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$REPO_ROOT/templates"
PASS=0; FAIL=0

assert() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name - expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local name="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name - pattern '$pattern' not found in $file"
  fi
}

assert_file_exists() {
  local name="$1" file="$2"
  if [ -f "$file" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name - file not found: $file"
  fi
}

# ── Section template existence ──────────────────────────────────────────────
assert_file_exists "principles.md exists" "$TEMPLATES/agents-sections/principles.md"
assert_file_exists "workflow.md exists"   "$TEMPLATES/agents-sections/workflow.md"
assert_file_exists "self-learning.md exists" "$TEMPLATES/agents-sections/self-learning.md"
assert_file_exists "authority.md exists"  "$TEMPLATES/agents-sections/authority.md"

# ── Type template existence ──────────────────────────────────────────────────
assert_file_exists "coding.md exists" "$TEMPLATES/agents-types/coding.md"
assert_file_exists "gtm.md exists"    "$TEMPLATES/agents-types/gtm.md"

# ── BEGIN/END markers ────────────────────────────────────────────────────────
assert_contains "principles BEGIN marker" "BEGIN OMK PRINCIPLES"   "$TEMPLATES/agents-sections/principles.md"
assert_contains "principles END marker"   "END OMK PRINCIPLES"     "$TEMPLATES/agents-sections/principles.md"
assert_contains "workflow BEGIN marker"   "BEGIN OMK WORKFLOW"     "$TEMPLATES/agents-sections/workflow.md"
assert_contains "workflow END marker"     "END OMK WORKFLOW"       "$TEMPLATES/agents-sections/workflow.md"
assert_contains "self-learning BEGIN"     "BEGIN OMK SELF-LEARNING" "$TEMPLATES/agents-sections/self-learning.md"
assert_contains "self-learning END"       "END OMK SELF-LEARNING"   "$TEMPLATES/agents-sections/self-learning.md"
assert_contains "authority BEGIN marker"  "BEGIN OMK AUTHORITY"    "$TEMPLATES/agents-sections/authority.md"
assert_contains "authority END marker"    "END OMK AUTHORITY"      "$TEMPLATES/agents-sections/authority.md"

# ── Key content sanity checks ────────────────────────────────────────────────
assert_contains "principles has Evidence" "Evidence before claims" "$TEMPLATES/agents-sections/principles.md"
assert_contains "workflow has Explore"    "Explore"                "$TEMPLATES/agents-sections/workflow.md"
assert_contains "workflow has Skill Routing" "Skill Routing"       "$TEMPLATES/agents-sections/workflow.md"
assert_contains "self-learning has episodes" "episodes.md"         "$TEMPLATES/agents-sections/self-learning.md"
assert_contains "authority has Authority Matrix" "Authority Matrix" "$TEMPLATES/agents-sections/authority.md"

# ── Type templates have required sections ────────────────────────────────────
assert_contains "coding has Identity"    "## Identity" "$TEMPLATES/agents-types/coding.md"
assert_contains "coding has Roles"       "## Roles"    "$TEMPLATES/agents-types/coding.md"
assert_contains "coding has Domain Rules" "## Domain Rules" "$TEMPLATES/agents-types/coding.md"
assert_contains "coding references OMK sections" "OMK SECTIONS" "$TEMPLATES/agents-types/coding.md"
assert_contains "gtm has Identity"       "## Identity" "$TEMPLATES/agents-types/gtm.md"
assert_contains "gtm has Roles"          "## Roles"    "$TEMPLATES/agents-types/gtm.md"
assert_contains "gtm has Domain Rules"   "## Domain Rules" "$TEMPLATES/agents-types/gtm.md"
assert_contains "gtm references OMK sections" "OMK SECTIONS" "$TEMPLATES/agents-types/gtm.md"

# ── Assembled AGENTS.md under 200 lines ──────────────────────────────────────
# Simulate assembly: concatenate one type template + all section templates
ASSEMBLED=$(cat \
  "$TEMPLATES/agents-types/coding.md" \
  "$TEMPLATES/agents-sections/principles.md" \
  "$TEMPLATES/agents-sections/workflow.md" \
  "$TEMPLATES/agents-sections/self-learning.md" \
  "$TEMPLATES/agents-sections/authority.md")
LINE_COUNT=$(echo "$ASSEMBLED" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -lt 200 ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  echo "FAIL: assembled AGENTS.md exceeds 200 lines (got $LINE_COUNT)"
fi

# ── Report ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
