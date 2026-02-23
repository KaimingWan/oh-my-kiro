#!/bin/bash
# Validate a project's OMCC overlay configuration
# Usage: validate-project.sh [PROJECT_ROOT]
# Exit 0: valid (warnings may be emitted)
# Exit 1: errors found

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMCC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
WARNINGS=0

err() { echo "ERROR: $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARNING: $*"; WARNINGS=$((WARNINGS + 1)); }

OVERLAY_FILE="$PROJECT_ROOT/.omcc-overlay.json"

# Valid hook event names (Claude Code / Kiro events)
VALID_EVENTS="PreToolUse PostToolUse Stop UserPromptSubmit TaskCompleted"

# ─── E1: Overlay file validation ──────────────────────────────────────────────
if [ -f "$OVERLAY_FILE" ]; then
  if ! [ -s "$OVERLAY_FILE" ]; then
    err "E1: .omcc-overlay.json is empty"
  elif ! jq empty "$OVERLAY_FILE" 2>/dev/null; then
    err "E1: .omcc-overlay.json is not valid JSON"
  fi
else
  # No overlay is fine — project may not use extension points
  :
fi

# Only proceed with overlay checks if file exists, non-empty, and valid JSON
OVERLAY_VALID=false
if [ -f "$OVERLAY_FILE" ] && [ -s "$OVERLAY_FILE" ] && jq empty "$OVERLAY_FILE" 2>/dev/null; then
  OVERLAY_VALID=true
fi

# ─── E2: extra_skills paths must have SKILL.md ────────────────────────────────
if [ "$OVERLAY_VALID" = true ]; then
  EXTRA_SKILLS=$(jq -r '.extra_skills[]? // empty' "$OVERLAY_FILE" 2>/dev/null || true)
  while IFS= read -r skill_path; do
    [ -z "$skill_path" ] && continue
    # Resolve relative to project root
    if [[ "$skill_path" != /* ]]; then
      skill_path="$PROJECT_ROOT/$skill_path"
    fi
    if [ ! -f "$skill_path/SKILL.md" ]; then
      err "E2: extra_skills path missing SKILL.md: $skill_path"
    else
      # W1: SKILL.md missing frontmatter
      if ! head -1 "$skill_path/SKILL.md" | grep -q '^---'; then
        warn "W1: SKILL.md missing frontmatter (---): $skill_path/SKILL.md"
      fi
      # W2: extra_skills not referenced in Skill Routing table
      skill_name=$(basename "$skill_path")
      agents_md="$PROJECT_ROOT/AGENTS.md"
      if [ -f "$agents_md" ] && ! grep -q "$skill_name" "$agents_md" 2>/dev/null; then
        warn "W2: extra_skill '$skill_name' not referenced in Skill Routing section of AGENTS.md"
      fi
    fi
  done <<< "$EXTRA_SKILLS"
fi

# ─── E3 & E4: extra_hooks command existence + valid event names ───────────────
if [ "$OVERLAY_VALID" = true ]; then
  # extra_hooks is expected as: {"EventName": ["cmd1", "cmd2"], ...}
  HOOK_EVENTS=$(jq -r '.extra_hooks | keys[]? // empty' "$OVERLAY_FILE" 2>/dev/null || true)
  while IFS= read -r event; do
    [ -z "$event" ] && continue

    # E4: validate event name
    if ! echo "$VALID_EVENTS" | grep -qw "$event"; then
      err "E4: extra_hooks invalid event name: '$event' (valid: $VALID_EVENTS)"
      continue
    fi

    # E3: validate each command exists and is executable
    # Support both string format ["cmd"] and dict format [{"command":"cmd"}]
    CMDS=$(jq -r --arg e "$event" '.extra_hooks[$e][]? | if type == "object" then .command else . end // empty' "$OVERLAY_FILE" 2>/dev/null || true)
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      # Extract just the command (first word), resolve relative to project root
      cmd_bin="${cmd%% *}"
      if [[ "$cmd_bin" != /* ]]; then
        cmd_bin="$PROJECT_ROOT/$cmd_bin"
      fi
      if [ ! -f "$cmd_bin" ] || [ ! -x "$cmd_bin" ]; then
        err "E3: extra_hooks command missing or not executable: $cmd_bin"
      else
        # W3: project hook name similar to framework hook name
        hook_basename=$(basename "$cmd_bin")
        framework_hooks=$(find "$OMCC_ROOT/hooks" -name "*.sh" -exec basename {} \; 2>/dev/null || true)
        while IFS= read -r fw_hook; do
          [ -z "$fw_hook" ] && continue
          if [ "$hook_basename" = "$fw_hook" ]; then
            warn "W3: project hook name '$hook_basename' matches framework hook name exactly — may cause confusion"
          fi
        done <<< "$framework_hooks"
      fi
    done <<< "$CMDS"
  done <<< "$HOOK_EVENTS"
fi

# ─── E5: project skill name conflicts framework skill ─────────────────────────
if [ "$OVERLAY_VALID" = true ]; then
  FRAMEWORK_SKILLS_DIR="$OMCC_ROOT/skills"
  EXTRA_SKILLS=$(jq -r '.extra_skills[]? // empty' "$OVERLAY_FILE" 2>/dev/null || true)
  while IFS= read -r skill_path; do
    [ -z "$skill_path" ] && continue
    skill_name=$(basename "$skill_path")
    if [ -d "$FRAMEWORK_SKILLS_DIR/$skill_name" ]; then
      err "E5: project skill name '$skill_name' conflicts with framework skill in $FRAMEWORK_SKILLS_DIR"
    fi
  done <<< "$EXTRA_SKILLS"
fi

# ─── E6: AGENTS.md BEGIN/END markers ─────────────────────────────────────────
AGENTS_MD="$PROJECT_ROOT/AGENTS.md"
if [ -f "$AGENTS_MD" ]; then
  if ! grep -q '<!-- BEGIN OMCC' "$AGENTS_MD" 2>/dev/null; then
    err "E6: AGENTS.md missing <!-- BEGIN OMCC ... --> markers"
  fi
  if ! grep -q '<!-- END OMCC' "$AGENTS_MD" 2>/dev/null; then
    err "E6: AGENTS.md missing <!-- END OMCC ... --> markers"
  fi
  # W5: AGENTS.md >200 lines
  line_count=$(wc -l < "$AGENTS_MD")
  if [ "$line_count" -gt 200 ]; then
    warn "W5: AGENTS.md is $line_count lines (>200) — consider trimming"
  fi
fi

# ─── E7: key symlinks ─────────────────────────────────────────────────────────
for link in ".claude/hooks" ".kiro/hooks" ".claude/skills" ".kiro/skills"; do
  link_path="$PROJECT_ROOT/$link"
  if [ -L "$link_path" ] && [ ! -e "$link_path" ]; then
    err "E7: broken symlink: $link_path"
  fi
done

# ─── E8: knowledge/INDEX.md missing or empty ──────────────────────────────────
KNOWLEDGE_INDEX="$PROJECT_ROOT/knowledge/INDEX.md"
if [ ! -f "$KNOWLEDGE_INDEX" ]; then
  err "E8: knowledge/INDEX.md missing"
elif [ ! -s "$KNOWLEDGE_INDEX" ]; then
  err "E8: knowledge/INDEX.md is empty"
fi


# ─── W6: knowledge/episodes.md and rules.md missing ──────────────────────────
for kf in episodes.md rules.md; do
  if [ ! -f "$PROJECT_ROOT/knowledge/$kf" ]; then
    warn "W6: knowledge/$kf missing — self-learning chain will not function"
  fi
done

# ─── W4: knowledge files >50KB ────────────────────────────────────────────────
if [ -d "$PROJECT_ROOT/knowledge" ]; then
  while IFS= read -r kfile; do
    [ -z "$kfile" ] && continue
    file_size=$(stat -f%z "$kfile" 2>/dev/null || stat -c%s "$kfile" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 51200 ]; then
      warn "W4: knowledge file >50KB ($file_size bytes): $kfile"
    fi
  done < <(find "$PROJECT_ROOT/knowledge" -type f -name "*.md" 2>/dev/null)
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "❌ Validation failed: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
else
  echo "✅ Validation passed ($WARNINGS warning(s))"
  exit 0
fi
