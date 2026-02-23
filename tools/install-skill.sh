#!/bin/bash
# Install a skill into a project's OMCC overlay
#
# Usage:
#   install-skill.sh --register-only PROJECT_ROOT SKILL_PATH
#     → Adds SKILL_PATH to .omcc-overlay.json extra_skills (no copy, no npx)
#
#   install-skill.sh SOURCE
#     → Runs `npx skills add SOURCE`, moves result to skills/, registers in overlay, runs sync
#
# Exit 0: success
# Exit 1: error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMCC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

err() { echo "ERROR: $*" >&2; exit 1; }

# ─── Injection/secret scan ─────────────────────────────────────────────────────
PATTERNS_LIB="$(cd "$(dirname "$0")/../hooks/_lib" 2>/dev/null && pwd)/patterns.sh"
if [ -f "$PATTERNS_LIB" ]; then
  source "$PATTERNS_LIB"
fi

scan_skill_file() {
  local skill_md="$1"
  [ ! -f "$skill_md" ] && return 0
  local content
  content=$(cat "$skill_md")
  if [ -n "${INJECTION_PATTERNS:-}" ] && echo "$content" | grep -qiE "$INJECTION_PATTERNS"; then
    err "Injection pattern detected in: $skill_md"
  fi
  if [ -n "${SECRET_PATTERNS:-}" ] && echo "$content" | grep -qiE "$SECRET_PATTERNS"; then
    err "Secret pattern detected in: $skill_md"
  fi
}


# ─── Overlay JSON helper ───────────────────────────────────────────────────────
# Adds a skill path to .omcc-overlay.json extra_skills (creates file if absent)
register_skill_in_overlay() {
  local overlay_file="$1"
  local skill_path="$2"

  if [ ! -f "$overlay_file" ]; then
    echo '{"extra_skills": [], "extra_hooks": {}}' > "$overlay_file"
  fi

  # Validate existing JSON before modifying
  if ! jq empty "$overlay_file" 2>/dev/null; then
    err "Overlay file is not valid JSON: $overlay_file"
  fi

  # Check if already registered (avoid duplicates)
  if jq -e --arg p "$skill_path" '.extra_skills | index($p) != null' "$overlay_file" >/dev/null 2>&1; then
    echo "ℹ️  Skill already registered: $skill_path"
    return 0
  fi

  # Append skill path to extra_skills array
  local tmp
  tmp=$(mktemp)
  jq --arg p "$skill_path" '.extra_skills += [$p]' "$overlay_file" > "$tmp"
  mv "$tmp" "$overlay_file"
  echo "✅ Registered skill in overlay: $skill_path"
}

# ─── Mode: --register-only ────────────────────────────────────────────────────
if [ "${1:-}" = "--register-only" ]; then
  [ $# -lt 3 ] && err "Usage: install-skill.sh --register-only PROJECT_ROOT SKILL_PATH"
  PROJECT_ROOT="$2"
  SKILL_PATH="$3"

  [ -d "$PROJECT_ROOT" ] || err "PROJECT_ROOT does not exist: $PROJECT_ROOT"

  OVERLAY_FILE="$PROJECT_ROOT/.omcc-overlay.json"

  # Resolve skill path relative to project root if not absolute
  if [[ "$SKILL_PATH" != /* ]]; then
    ABS_SKILL_PATH="$PROJECT_ROOT/$SKILL_PATH"
  else
    ABS_SKILL_PATH="$SKILL_PATH"
  fi

  # Validate SKILL.md exists
  [ -f "$ABS_SKILL_PATH/SKILL.md" ] || err "SKILL.md not found at: $ABS_SKILL_PATH/SKILL.md"

  scan_skill_file "$ABS_SKILL_PATH/SKILL.md"

  register_skill_in_overlay "$OVERLAY_FILE" "$SKILL_PATH"
  exit 0
fi

# ─── Mode: SOURCE (npx install) ───────────────────────────────────────────────
[ $# -lt 1 ] && err "Usage: install-skill.sh --register-only PROJECT_ROOT SKILL_PATH
       install-skill.sh SOURCE"

SOURCE="$1"
PROJECT_ROOT="${2:-$(pwd)}"

[ -d "$PROJECT_ROOT" ] || err "PROJECT_ROOT does not exist: $PROJECT_ROOT"

SKILLS_DIR="$PROJECT_ROOT/skills"
OVERLAY_FILE="$PROJECT_ROOT/.omcc-overlay.json"

# Check that npx is available
command -v npx >/dev/null 2>&1 || err "npx not found — install Node.js to use SOURCE mode"

# Run npx skills add to download the skill
echo "📦 Running: npx skills add $SOURCE"
TMP_INSTALL_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_INSTALL_DIR"' EXIT

# npx skills add installs to current dir by default; we run it in temp dir
# then move the result to skills/
pushd "$TMP_INSTALL_DIR" >/dev/null
npx skills add "$SOURCE"
popd >/dev/null

# Find the downloaded skill directory (should be the only directory created)
INSTALLED_DIRS=()
while IFS= read -r d; do
  INSTALLED_DIRS+=("$d")
done < <(find "$TMP_INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

if [ ${#INSTALLED_DIRS[@]} -eq 0 ]; then
  err "No skill directory found after npx skills add $SOURCE"
fi

mkdir -p "$SKILLS_DIR"

for installed_dir in "${INSTALLED_DIRS[@]}"; do
  skill_name=$(basename "$installed_dir")
  dest="$SKILLS_DIR/$skill_name"

  if [ -d "$dest" ]; then
    echo "⚠️  Skill directory already exists, overwriting: $dest"
    rm -rf "$dest"
  fi

  mv "$installed_dir" "$dest"
  echo "📂 Moved skill to: $dest"

  # Scan for injection/secrets before registering
  scan_skill_file "$dest/SKILL.md"

  # Register in overlay (use relative path)
  relative_path="skills/$skill_name"
  register_skill_in_overlay "$OVERLAY_FILE" "$relative_path"
done

# Validate and sync
SYNC_SCRIPT="$SCRIPT_DIR/sync-omcc.sh"
if [ -f "$SYNC_SCRIPT" ]; then
  echo "🔄 Running sync-omcc..."
  bash "$SYNC_SCRIPT" "$PROJECT_ROOT"
else
  echo "ℹ️  sync-omcc.sh not found, skipping sync"
fi
