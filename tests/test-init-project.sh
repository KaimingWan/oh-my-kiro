#!/bin/bash
# Tests for tools/init-project.sh --type and overlay scaffolding
# Note: no set -e — test harness must survive individual test failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$ROOT_DIR/tools/init-project.sh"

PASS=0
FAIL=0
ERRORS=()

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

run_test() {
  local name="$1"
  local fn="$2"
  echo "▶ $name"
  "$fn" || true
}

# Create a fresh temp target dir
make_target() {
  mktemp -d
}

cleanup() {
  local dir="$1"
  [ -n "$dir" ] && [ -d "$dir" ] && mv "$dir" ~/.Trash/ 2>/dev/null || true
}

# ── Test: default (no --type) is backward compatible ────────────────────────
test_default_no_type() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "TestProject" >/dev/null 2>&1

  # Core files must exist
  if [ -f "$target/CLAUDE.md" ]; then pass "default: CLAUDE.md created"; else fail "default: CLAUDE.md missing"; fi
  if [ -f "$target/AGENTS.md" ]; then pass "default: AGENTS.md created"; else fail "default: AGENTS.md missing"; fi

  # Project name substituted in pilot.json agent description
  if jq -e '.description | test("TestProject")' "$target/.kiro/agents/pilot.json" >/dev/null 2>&1; then
    pass "default: project name substituted in pilot.json"
  else
    fail "default: project name not substituted in pilot.json"
  fi
}

# ── Test: --type coding assembles AGENTS.md from templates ──────────────────
test_type_coding() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "CodingProj" --type coding >/dev/null 2>&1

  if [ -f "$target/AGENTS.md" ]; then pass "--type coding: AGENTS.md created"; else fail "--type coding: AGENTS.md missing"; return; fi

  # Should contain coding identity
  if grep -q "Coding agent" "$target/AGENTS.md" 2>/dev/null; then
    pass "--type coding: coding identity present"
  else
    fail "--type coding: coding identity missing"
  fi

  # Should contain OMK sections (assembled)
  if grep -q "BEGIN OMK PRINCIPLES" "$target/AGENTS.md" 2>/dev/null; then
    pass "--type coding: principles section present"
  else
    fail "--type coding: principles section missing"
  fi

  if grep -q "BEGIN OMK WORKFLOW" "$target/AGENTS.md" 2>/dev/null; then
    pass "--type coding: workflow section present"
  else
    fail "--type coding: workflow section missing"
  fi

  # Project name substituted in pilot.json
  if jq -e '.description | test("CodingProj")' "$target/.kiro/agents/pilot.json" >/dev/null 2>&1; then
    pass "--type coding: project name substituted in pilot.json"
  else
    fail "--type coding: project name not substituted in pilot.json"
  fi

  # Under 200 lines
  local lines
  lines=$(wc -l < "$target/AGENTS.md")
  if [ "$lines" -lt 200 ]; then
    pass "--type coding: AGENTS.md under 200 lines ($lines)"
  else
    fail "--type coding: AGENTS.md too long ($lines lines, max 200)"
  fi
}

# ── Test: --type gtm assembles AGENTS.md from templates ─────────────────────
test_type_gtm() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "GTMProj" --type gtm >/dev/null 2>&1

  if [ -f "$target/AGENTS.md" ]; then pass "--type gtm: AGENTS.md created"; else fail "--type gtm: AGENTS.md missing"; return; fi

  if grep -q "GTM" "$target/AGENTS.md" 2>/dev/null; then
    pass "--type gtm: GTM identity present"
  else
    fail "--type gtm: GTM identity missing"
  fi

  if grep -q "BEGIN OMK PRINCIPLES" "$target/AGENTS.md" 2>/dev/null; then
    pass "--type gtm: principles section present"
  else
    fail "--type gtm: principles section missing"
  fi
}

# ── Test: creates .omk-overlay.json ────────────────────────────────────────
test_overlay_json_created() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "OverlayProj" >/dev/null 2>&1

  if [ -f "$target/.omk-overlay.json" ]; then
    pass "overlay: .omk-overlay.json created"
    # Must be valid JSON
    if jq . "$target/.omk-overlay.json" >/dev/null 2>&1; then
      pass "overlay: .omk-overlay.json is valid JSON"
    else
      fail "overlay: .omk-overlay.json is invalid JSON"
    fi
  else
    fail "overlay: .omk-overlay.json missing"
  fi
}

# ── Test: creates hooks/project/ directory ───────────────────────────────────
test_hooks_project_dir() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "HooksProj" >/dev/null 2>&1

  if [ -d "$target/hooks/project" ]; then
    pass "hooks: hooks/project/ directory created"
  else
    fail "hooks: hooks/project/ directory missing"
  fi
}

# ── Test: copies EXTENSION-GUIDE.md if it exists ────────────────────────────
test_extension_guide_copied() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  bash "$INIT_SCRIPT" "$target" "GuideProj" >/dev/null 2>&1

  # Only assert if source exists
  if [ -f "$ROOT_DIR/docs/EXTENSION-GUIDE.md" ]; then
    if [ -f "$target/docs/EXTENSION-GUIDE.md" ]; then
      pass "extension-guide: EXTENSION-GUIDE.md copied"
    else
      fail "extension-guide: EXTENSION-GUIDE.md not copied"
    fi
  else
    pass "extension-guide: source missing, skipped (Task 6 not yet done)"
  fi
}

# ── Test: aborts if AGENTS.md already exists ────────────────────────────────
test_abort_if_exists() {
  local target
  target=$(make_target)
  trap "cleanup '$target'" RETURN

  touch "$target/AGENTS.md"

  if bash "$INIT_SCRIPT" "$target" "ExistsProj" >/dev/null 2>&1; then
    fail "abort: should have aborted on existing AGENTS.md"
  else
    pass "abort: correctly aborted on existing AGENTS.md"
  fi
}

# ── Test: fallback when templates/ missing ───────────────────────────────────
test_fallback_no_templates() {
  local target fake_root
  target=$(make_target)
  fake_root=$(make_target)
  trap "cleanup '$target'; cleanup '$fake_root'" RETURN

  # Set up minimal fake OMK root (no templates/)
  cp "$ROOT_DIR/CLAUDE.md" "$fake_root/"
  cp "$ROOT_DIR/AGENTS.md" "$fake_root/"
  mkdir -p "$fake_root/.claude" && cp "$ROOT_DIR/.claude/settings.json" "$fake_root/.claude/"
  mkdir -p "$fake_root/.kiro/rules" && cp "$ROOT_DIR/.kiro/rules/"*.md "$fake_root/.kiro/rules/"
  cp -r "$ROOT_DIR/hooks" "$fake_root/"
  mkdir -p "$fake_root/.kiro/agents" && cp "$ROOT_DIR/.kiro/agents/"*.json "$fake_root/.kiro/agents/"
  mkdir -p "$fake_root/knowledge/product" && cp "$ROOT_DIR/knowledge/"*.md "$fake_root/knowledge/"
  mkdir -p "$fake_root/docs" && cp "$ROOT_DIR/docs/INDEX.md" "$fake_root/docs/"
  cp "$ROOT_DIR/.gitignore" "$fake_root/" 2>/dev/null || true

  # Run init pointing to fake_root as the template dir (override via env or symlink trick)
  # We do this by temporarily symlinking; instead use OMK_ROOT env var if supported,
  # or just run with the script from fake_root
  # Since the script uses dirname-based TEMPLATE_DIR, symlink the script
  local fake_script="$fake_root/tools/init-project.sh"
  mkdir -p "$fake_root/tools"
  cp "$INIT_SCRIPT" "$fake_script"
  chmod +x "$fake_script"

  bash "$fake_script" "$target" "FallbackProj" --type coding >/dev/null 2>&1

  if [ -f "$target/AGENTS.md" ]; then
    pass "fallback: AGENTS.md created even without templates/"
  else
    fail "fallback: AGENTS.md missing when templates/ absent"
  fi
}

# ── Run all tests ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo " test-init-project.sh"
echo "═══════════════════════════════════════════════════"
echo ""

run_test "Default (no --type) backward compatible" test_default_no_type
run_test "--type coding assembles AGENTS.md" test_type_coding
run_test "--type gtm assembles AGENTS.md" test_type_gtm
run_test "Creates .omk-overlay.json" test_overlay_json_created
run_test "Creates hooks/project/ directory" test_hooks_project_dir
run_test "Copies EXTENSION-GUIDE.md if exists" test_extension_guide_copied
run_test "Aborts if AGENTS.md already exists" test_abort_if_exists
run_test "Fallback when templates/ missing" test_fallback_no_templates

echo ""
echo "═══════════════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  echo ""
fi

[ "$FAIL" -eq 0 ]
