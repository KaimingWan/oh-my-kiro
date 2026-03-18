#!/bin/bash
# test-boundary-check.sh — Detect host-project code that should live in oh-my-kiro/
# Checks: 1) Duplicated hook scripts (copy vs symlink) 2) Generic logic in host skills
set -euo pipefail

WARN_COUNT=0
warn() { echo "WARN: $1"; WARN_COUNT=$((WARN_COUNT + 1)); }

# Resolve project root (parent of oh-my-kiro/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$OMK_ROOT/.." && pwd)"

# ── Check 1: Duplicated hooks (same content, not symlink) ──
if [ -d "$PROJECT_ROOT/hooks" ]; then
  for host_hook in "$PROJECT_ROOT/hooks"/*.sh; do
    [ -f "$host_hook" ] || continue
    [ -L "$host_hook" ] && continue  # symlink is fine
    base=$(basename "$host_hook")
    # Search for same-named file in oh-my-kiro/hooks/
    omk_match=$(find "$OMK_ROOT/hooks" -name "$base" -type f 2>/dev/null | head -1)
    [ -z "$omk_match" ] && continue
    if diff -q "$host_hook" "$omk_match" >/dev/null 2>&1; then
      warn "hooks/$base is a copy of oh-my-kiro/hooks/.../$base — should be a symlink"
    fi
  done
fi

# ── Check 2: Generic logic keywords in host skills ──
GENERIC_KEYWORDS="middleware|hook|dispatch|enrichment|distill|harness"
if [ -d "$PROJECT_ROOT/skills" ]; then
  for skill_md in "$PROJECT_ROOT/skills"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    rel=$(echo "$skill_md" | sed "s|$PROJECT_ROOT/||")
    if grep -qiE "$GENERIC_KEYWORDS" "$skill_md" 2>/dev/null; then
      # Skip if it's a symlink into oh-my-kiro
      [ -L "$skill_md" ] && continue
      # Check if same skill exists in oh-my-kiro
      skill_name=$(basename "$(dirname "$skill_md")")
      [ -d "$OMK_ROOT/skills/$skill_name" ] && continue  # already in OMK
      warn "$rel contains generic logic keywords — consider moving to oh-my-kiro/"
    fi
  done
fi

# ── Report ──
if [ "$WARN_COUNT" -gt 0 ]; then
  echo "WARN: $WARN_COUNT items should be in oh-my-kiro/"
else
  echo "PASS"
fi
exit 0
