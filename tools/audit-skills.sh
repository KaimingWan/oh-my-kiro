#!/bin/bash
# audit-skills.sh — Scan all installed skills for injection/secret patterns
# Usage: audit-skills.sh [PROJECT_ROOT]
# Exit 0: clean, Exit 1: issues found

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_LIB="$SCRIPT_DIR/../hooks/_lib/patterns.sh"

[ -f "$PATTERNS_LIB" ] && source "$PATTERNS_LIB"

ISSUES=0
SCANNED=0

for skill_dir in "$PROJECT_ROOT/skills/"*/; do
  [ -d "$skill_dir" ] || continue
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue
  SCANNED=$((SCANNED + 1))
  content=$(cat "$skill_md")
  skill_name=$(basename "$skill_dir")

  if [ -n "${INJECTION_PATTERNS:-}" ] && echo "$content" | grep -qiE "$INJECTION_PATTERNS"; then
    echo "❌ INJECTION: $skill_name ($skill_md)"
    ISSUES=$((ISSUES + 1))
  fi
  if [ -n "${SECRET_PATTERNS:-}" ] && echo "$content" | grep -qiE "$SECRET_PATTERNS"; then
    echo "❌ SECRET: $skill_name ($skill_md)"
    ISSUES=$((ISSUES + 1))
  fi
done

echo "Scanned $SCANNED skills, $ISSUES issue(s) found."
[ "$ISSUES" -eq 0 ]
