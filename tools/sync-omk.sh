#!/bin/bash
# Sync a project with the latest OMK framework
#
# Usage: sync-omk.sh [PROJECT_ROOT]
#   PROJECT_ROOT: path to project directory (default: current directory)
#
# Steps:
#   1. Submodule update (if project uses OMK as a submodule)
#   2. Validate project overlay (.omcc-overlay.json)
#   3. Generate agent configs (generate_configs.py --overlay)
#   4. Update AGENTS.md framework sections (BEGIN/END OMK markers)
#
# Exit 0: success
# Exit 1: error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_ROOT="${1:-$(pwd)}"

err() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }

[ -d "$PROJECT_ROOT" ] || err "PROJECT_ROOT does not exist: $PROJECT_ROOT"

echo "🔄 Syncing OMK for project: $PROJECT_ROOT"
echo ""

# ─── Step 1: Submodule update ─────────────────────────────────────────────────
# Only run if the project root is a git repo and has OMK as a submodule
if [ -f "$PROJECT_ROOT/.gitmodules" ] && grep -q "oh-my-kiro\|omcc" "$PROJECT_ROOT/.gitmodules" 2>/dev/null; then
  info "Step 1: Updating OMK submodule..."
  (cd "$PROJECT_ROOT" && git submodule update --init --remote oh-my-kiro 2>/dev/null || \
   git submodule update --init --remote omk 2>/dev/null || \
   git submodule update --init --remote 2>/dev/null) || {
    echo "⚠️  Submodule update failed or not applicable, continuing..."
  }
  ok "Step 1: Submodule up to date"
else
  info "Step 1: No OMK submodule detected, skipping submodule update"
fi

# ─── Step 1.5: Sync framework hooks ──────────────────────────────────────────
# Sync OMK hooks to project BEFORE validation. Framework dirs
# (security/gate/feedback/_lib) are rsync'd. Dispatch scripts overwritten.
# hooks/project/ is never touched (project-specific extensions).
OMK_HOOKS="$OMK_ROOT/hooks"
PROJECT_HOOKS="$PROJECT_ROOT/hooks"
if [ -d "$OMK_HOOKS" ] && [ -d "$PROJECT_HOOKS" ]; then
  HOOKS_SYNCED=0
  for hook_subdir in security gate feedback _lib; do
    if [ -d "$OMK_HOOKS/$hook_subdir" ]; then
      mkdir -p "$PROJECT_HOOKS/$hook_subdir"
      rsync -a "$OMK_HOOKS/$hook_subdir/" "$PROJECT_HOOKS/$hook_subdir/"
      HOOKS_SYNCED=$((HOOKS_SYNCED + 1))
    fi
  done
  for dispatch in "$OMK_HOOKS"/dispatch-*.sh; do
    [ -f "$dispatch" ] || continue
    cp "$dispatch" "$PROJECT_HOOKS/$(basename "$dispatch")"
    chmod +x "$PROJECT_HOOKS/$(basename "$dispatch")"
    HOOKS_SYNCED=$((HOOKS_SYNCED + 1))
  done
  ok "Step 1.5: Hooks synced ($HOOKS_SYNCED items from OMK, project/ untouched)"
else
  if [ -d "$OMK_HOOKS" ] && [ ! -d "$PROJECT_HOOKS" ]; then
    mkdir -p "$PROJECT_HOOKS"
    rsync -a "$OMK_HOOKS/" "$PROJECT_HOOKS/" --exclude='project/'
    ok "Step 1.5: Hooks directory created from OMK"
  else
    info "Step 1.5: hooks/ not found in OMK, skipping"
  fi
fi

# ─── Step 2: Validate project overlay ────────────────────────────────────────
info "Step 2: Validating project overlay..."
VALIDATE_SCRIPT="$OMK_ROOT/tools/validate-project.sh"
if [ ! -f "$VALIDATE_SCRIPT" ]; then
  err "validate-project.sh not found at: $VALIDATE_SCRIPT"
fi

if ! bash "$VALIDATE_SCRIPT" "$PROJECT_ROOT"; then
  err "Step 2: Validation failed — fix errors before syncing"
fi
ok "Step 2: Validation passed"

# ─── Step 3: Generate agent configs ──────────────────────────────────────────
info "Step 3: Generating agent configs..."
GENERATE_SCRIPT="$OMK_ROOT/scripts/generate_configs.py"
if [ ! -f "$GENERATE_SCRIPT" ]; then
  err "generate_configs.py not found at: $GENERATE_SCRIPT"
fi

OVERLAY_FILE="$PROJECT_ROOT/.omk-overlay.json"
if [ ! -f "$OVERLAY_FILE" ] && [ -f "$PROJECT_ROOT/.omcc-overlay.json" ]; then
  echo "⚠️  .omcc-overlay.json is deprecated, rename to .omk-overlay.json"
  OVERLAY_FILE="$PROJECT_ROOT/.omcc-overlay.json"
fi
GENERATE_CMD="python3 $GENERATE_SCRIPT --project-root $PROJECT_ROOT --skip-validate"
if [ -f "$OVERLAY_FILE" ]; then
  GENERATE_CMD="$GENERATE_CMD --overlay $OVERLAY_FILE"
fi

if ! eval "$GENERATE_CMD"; then
  err "Step 3: Config generation failed"
fi
ok "Step 3: Agent configs generated"

# ─── Step 3.5: Ensure commands symlink ────────────────────────────────────────
if [ -d "$OMK_ROOT/commands" ] && [ ! -e "$PROJECT_ROOT/commands" ] && [ ! -L "$PROJECT_ROOT/commands" ]; then
  ln -s .omk/commands "$PROJECT_ROOT/commands"
  ok "Step 3.5: commands/ symlink created"
elif [ -L "$PROJECT_ROOT/commands" ]; then
  info "Step 3.5: commands/ symlink already exists"
else
  info "Step 3.5: commands/ directory exists (not a symlink), skipping"
fi

# ─── Step 3.6: Sync OMK commands to .kiro/prompts (Kiro CLI custom commands) ──
# IMPORTANT: Commands that are also exposed as MCP prompts (with {content} args)
# must NOT be copied to .kiro/prompts/ — file-based prompts take precedence over
# MCP prompts in Kiro, which breaks argument passing.
KIRO_PROMPTS="$PROJECT_ROOT/.kiro/prompts"
OMK_COMMANDS="$OMK_ROOT/commands"
MCP_PROMPTS_PY="$OMK_ROOT/scripts/mcp-prompts.py"

# Build skip list from MCP prompt names
MCP_SKIP=""
if [ -f "$MCP_PROMPTS_PY" ]; then
  MCP_SKIP=$(grep -A1 "@mcp.prompt" "$MCP_PROMPTS_PY" | grep "def " | sed 's/def \([a-z_]*\).*/\1/' | tr '\n' '|')
fi

_is_mcp_prompt() {
  local name="$1"
  [ -z "$MCP_SKIP" ] && return 1
  echo "$MCP_SKIP" | grep -qw "$name"
}

if [ -d "$PROJECT_ROOT/.kiro" ] && [ -d "$OMK_COMMANDS" ]; then
  # If .kiro/prompts is a symlink, convert to real directory (symlinks cause
  # MCP prompt shadowing when commands/ contains MCP-duplicate files)
  if [ -L "$KIRO_PROMPTS" ]; then
    LINK_TARGET=$(cd "$(dirname "$KIRO_PROMPTS")" && readlink "$(basename "$KIRO_PROMPTS")")
    unlink "$KIRO_PROMPTS"
    mkdir -p "$KIRO_PROMPTS"
    # Resolve the symlink target relative to .kiro/
    RESOLVED_DIR="$PROJECT_ROOT/.kiro/$LINK_TARGET"
    if [ -d "$RESOLVED_DIR" ]; then
      for f in "$RESOLVED_DIR"/*.md; do
        [ -f "$f" ] || continue
        fname=$(basename "$f" .md)
        _is_mcp_prompt "$fname" && continue
        cp "$f" "$KIRO_PROMPTS/"
      done
    fi
    ok "Step 3.6: Converted .kiro/prompts symlink to directory (MCP duplicates excluded)"
  fi

  if [ ! -e "$KIRO_PROMPTS" ]; then
    mkdir -p "$KIRO_PROMPTS"
    for f in "$OMK_COMMANDS"/*.md; do
      [ -f "$f" ] || continue
      fname=$(basename "$f" .md)
      _is_mcp_prompt "$fname" && continue
      cp "$f" "$KIRO_PROMPTS/"
    done
    ok "Step 3.6: .kiro/prompts/ created with OMK commands (MCP duplicates excluded)"
  else
    # Real directory — merge OMK commands (don't overwrite project-specific ones)
    CMDS_ADDED=0
    CMDS_UPDATED=0
    CMDS_SKIPPED=0
    for cmd_file in "$OMK_COMMANDS"/*.md; do
      [ -f "$cmd_file" ] || continue
      cmd_name=$(basename "$cmd_file" .md)
      # Skip commands that MCP already exposes (to avoid shadowing)
      if _is_mcp_prompt "$cmd_name"; then
        # Remove if previously synced (cleanup stale file-based duplicates AND symlinks)
        if [ -e "$KIRO_PROMPTS/$cmd_name.md" ] || [ -L "$KIRO_PROMPTS/$cmd_name.md" ]; then
          mv "$KIRO_PROMPTS/$cmd_name.md" ~/.Trash/ 2>/dev/null || rm -f "$KIRO_PROMPTS/$cmd_name.md"
          CMDS_SKIPPED=$((CMDS_SKIPPED + 1))
        fi
        continue
      fi
      if [ ! -f "$KIRO_PROMPTS/$cmd_name.md" ]; then
        cp "$cmd_file" "$KIRO_PROMPTS/$cmd_name.md"
        CMDS_ADDED=$((CMDS_ADDED + 1))
      elif [ "$cmd_file" -nt "$KIRO_PROMPTS/$cmd_name.md" ]; then
        if ! diff -q "$cmd_file" "$KIRO_PROMPTS/$cmd_name.md" >/dev/null 2>&1; then
          cp "$cmd_file" "$KIRO_PROMPTS/$cmd_name.md"
          CMDS_UPDATED=$((CMDS_UPDATED + 1))
        fi
      fi
    done
    if [ "$CMDS_ADDED" -gt 0 ] || [ "$CMDS_UPDATED" -gt 0 ] || [ "$CMDS_SKIPPED" -gt 0 ]; then
      ok "Step 3.6: Commands synced to .kiro/prompts/ ($CMDS_ADDED added, $CMDS_UPDATED updated, $CMDS_SKIPPED MCP-dupes removed)"
    else
      info "Step 3.6: .kiro/prompts/ commands already up to date"
    fi
  fi
else
  info "Step 3.6: .kiro/ or OMK commands/ not found, skipping"
fi

# ─── Step 3.7: Ensure scripts symlink (needed for ralph_loop.py) ──────────────
if [ -d "$OMK_ROOT/scripts" ] && [ ! -e "$PROJECT_ROOT/scripts" ]; then
  ln -s .omk/scripts "$PROJECT_ROOT/scripts"
  ok "Step 3.7: scripts/ symlink created"
elif [ -L "$PROJECT_ROOT/scripts" ]; then
  info "Step 3.7: scripts/ symlink already exists"
elif [ -d "$PROJECT_ROOT/scripts" ]; then
  info "Step 3.7: scripts/ is a real directory, skipping"
fi

# ─── Step 3.7.5: Sync agents/ prompt files (reviewer/researcher prompts) ──────
OMK_AGENTS="$OMK_ROOT/agents"
PROJECT_AGENTS="$PROJECT_ROOT/agents"
if [ -d "$OMK_AGENTS" ]; then
  mkdir -p "$PROJECT_AGENTS"
  AGENTS_SYNCED=0
  for f in "$OMK_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    if [ ! -f "$PROJECT_AGENTS/$fname" ] || ! diff -q "$f" "$PROJECT_AGENTS/$fname" >/dev/null 2>&1; then
      cp "$f" "$PROJECT_AGENTS/$fname"
      AGENTS_SYNCED=$((AGENTS_SYNCED + 1))
    fi
  done
  if [ "$AGENTS_SYNCED" -gt 0 ]; then
    ok "Step 3.7.5: agents/ prompt files synced ($AGENTS_SYNCED updated)"
  else
    info "Step 3.7.5: agents/ prompt files already up to date"
  fi
fi

# ─── Step 3.8: Ensure docs/plans/ directory (needed for @plan/@execute) ───────
mkdir -p "$PROJECT_ROOT/docs/plans"
info "Step 3.8: docs/plans/ ensured"

# ─── Step 3.9: Sync .kiro/settings/mcp.json (jq merge) ───────────────────────
OMK_MCP="$OMK_ROOT/.kiro/settings/mcp.json"
PROJECT_MCP="$PROJECT_ROOT/.kiro/settings/mcp.json"
if [ -f "$OMK_MCP" ]; then
  if [ ! -f "$PROJECT_MCP" ]; then
    mkdir -p "$(dirname "$PROJECT_MCP")"
    cp "$OMK_MCP" "$PROJECT_MCP"
    ok "Step 3.9: .kiro/settings/mcp.json copied from OMK (first-time sync)"
  elif command -v jq &>/dev/null; then
    jq -s '{"mcpServers": (.[0].mcpServers * .[1].mcpServers)}' "$PROJECT_MCP" "$OMK_MCP" > "${PROJECT_MCP}.tmp" && mv "${PROJECT_MCP}.tmp" "$PROJECT_MCP"
    ok "Step 3.9: .kiro/settings/mcp.json merged (OMK servers updated, project-custom preserved)"
  else
    info "Step 3.9: jq not available, skipping mcp.json merge"
  fi
else
  info "Step 3.9: OMK mcp.json not found, skipping"
fi

# ─── Step 3.10: Sync .kiro/rules/ framework files ────────────────────────────
# Copy OMK's .kiro/rules/ files to project, skip files that already exist
# (project-customized files take precedence)
OMK_KIRO_RULES="$OMK_ROOT/.kiro/rules"
PROJECT_KIRO_RULES="$PROJECT_ROOT/.kiro/rules"
if [ -d "$OMK_KIRO_RULES" ] && [ -d "$PROJECT_KIRO_RULES" ]; then
  RULES_SYNCED=0
  for rule_file in "$OMK_KIRO_RULES"/*.md; do
    [ -f "$rule_file" ] || continue
    rule_name=$(basename "$rule_file")
    if [ ! -f "$PROJECT_KIRO_RULES/$rule_name" ]; then
      cp "$rule_file" "$PROJECT_KIRO_RULES/$rule_name"
      RULES_SYNCED=$((RULES_SYNCED + 1))
    fi
  done
  if [ "$RULES_SYNCED" -gt 0 ]; then
    ok "Step 3.10: Synced $RULES_SYNCED new .kiro/rules/ file(s) from OMK"
  else
    info "Step 3.10: .kiro/rules/ already up to date"
  fi
else
  info "Step 3.10: .kiro/rules/ source or target not found, skipping"
fi



# ─── Step 3.10.5: Sync framework skills ──────────────────────────────────────
# Copy new/updated OMK skills to project. Project-only skills are untouched.
OMK_SKILLS="$OMK_ROOT/skills"
PROJECT_SKILLS="$PROJECT_ROOT/skills"
KIRO_SKILLS="$PROJECT_ROOT/.kiro/skills"
AUDIT_SCRIPT="$OMK_ROOT/tools/audit-skill.sh"
if [ -d "$OMK_SKILLS" ] && [ -d "$PROJECT_SKILLS" ] && [ -d "$KIRO_SKILLS" ]; then
  SKILLS_ADDED=0
  SKILLS_UPDATED=0
  SKILLS_BLOCKED=0
  for skill_dir in "$OMK_SKILLS"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    target="$PROJECT_SKILLS/$skill_name"

    # Security audit before sync
    if [ -f "$AUDIT_SCRIPT" ]; then
      if ! bash "$AUDIT_SCRIPT" "$skill_dir" >/dev/null 2>&1; then
        echo "  ⚠️  Skill '$skill_name' failed security audit, skipping"
        SKILLS_BLOCKED=$((SKILLS_BLOCKED + 1))
        continue
      fi
    fi

    if [ ! -d "$target" ]; then
      cp -r "$skill_dir" "$target"
      ln -sf "../../skills/$skill_name" "$KIRO_SKILLS/$skill_name"
      SKILLS_ADDED=$((SKILLS_ADDED + 1))
    else
      # Update existing framework skill (overwrite SKILL.md + resources)
      rsync -a --delete "$skill_dir" "$target/"
      # Ensure symlink exists
      [ -L "$KIRO_SKILLS/$skill_name" ] || ln -sf "../../skills/$skill_name" "$KIRO_SKILLS/$skill_name"
      SKILLS_UPDATED=$((SKILLS_UPDATED + 1))
    fi
  done
  if [ "$SKILLS_ADDED" -gt 0 ] || [ "$SKILLS_UPDATED" -gt 0 ] || [ "$SKILLS_BLOCKED" -gt 0 ]; then
    ok "Step 3.10.5: Skills synced ($SKILLS_ADDED added, $SKILLS_UPDATED updated, $SKILLS_BLOCKED blocked)"
  else
    info "Step 3.10.5: Skills already up to date"
  fi
else
  info "Step 3.10.5: skills/ directory not found in OMK or project, skipping"
fi

# ─── Step 3.11: Ensure knowledge/episodes.md and rules.md exist ───────────────
KNOWLEDGE_DIR="$PROJECT_ROOT/knowledge"
TEMPLATES_DIR="$OMK_ROOT/templates/knowledge"
if [ -d "$KNOWLEDGE_DIR" ] && [ -d "$TEMPLATES_DIR" ]; then
  for tmpl in episodes.md rules.md; do
    if [ ! -f "$KNOWLEDGE_DIR/$tmpl" ] && [ -f "$TEMPLATES_DIR/$tmpl" ]; then
      cp "$TEMPLATES_DIR/$tmpl" "$KNOWLEDGE_DIR/$tmpl"
      ok "Step 3.11: Created missing $tmpl from template"
    fi
  done
  info "Step 3.11: Knowledge files checked"
else
  info "Step 3.11: knowledge/ or templates/ not found, skipping"
fi
# ─── Step 4: Update AGENTS.md framework sections ──────────────────────────────
info "Step 4: Updating AGENTS.md framework sections..."
AGENTS_MD="$PROJECT_ROOT/AGENTS.md"
OMK_AGENTS_MD="$OMK_ROOT/AGENTS.md"

if [ ! -f "$AGENTS_MD" ]; then
  info "No AGENTS.md in project, skipping section update"
elif [ ! -f "$OMK_AGENTS_MD" ]; then
  info "No AGENTS.md in OMK root, skipping section update"
else
  # For each BEGIN/END OMK section in the OMK AGENTS.md, update matching section in project
  SECTIONS_UPDATED=0
  SECTIONS_SKIPPED=0

  # Extract section names from OMK AGENTS.md
  while IFS= read -r section_name; do
    [ -z "$section_name" ] && continue

    # Check if project AGENTS.md has this section
    if ! grep -q "<!-- BEGIN OMK $section_name -->" "$AGENTS_MD" 2>/dev/null; then
      SECTIONS_SKIPPED=$((SECTIONS_SKIPPED + 1))
      continue
    fi

    # Extract section content from OMK AGENTS.md (including markers)
    OMK_SECTION=$(awk "/<!-- BEGIN OMK $section_name -->/,/<!-- END OMK $section_name -->/" "$OMK_AGENTS_MD" 2>/dev/null || true)
    if [ -z "$OMK_SECTION" ]; then
      SECTIONS_SKIPPED=$((SECTIONS_SKIPPED + 1))
      continue
    fi

    # Create temp file for updated AGENTS.md
    TMP_AGENTS=$(mktemp)
    trap 'rm -f "$TMP_AGENTS"' EXIT

    # Replace section in project AGENTS.md using awk
    awk -v section="$section_name" -v new_content="$OMK_SECTION" '
      /<!-- BEGIN OMK / && index($0, "<!-- BEGIN OMK " section " -->") > 0 {
        print new_content
        skip = 1
        next
      }
      /<!-- END OMK / && index($0, "<!-- END OMK " section " -->") > 0 {
        skip = 0
        next
      }
      !skip { print }
    ' "$AGENTS_MD" > "$TMP_AGENTS"

    mv "$TMP_AGENTS" "$AGENTS_MD"
    SECTIONS_UPDATED=$((SECTIONS_UPDATED + 1))
  done < <(grep -oP '(?<=<!-- BEGIN OMK ).*(?= -->)' "$OMK_AGENTS_MD" 2>/dev/null || true)

  ok "Step 4: AGENTS.md updated ($SECTIONS_UPDATED sections updated, $SECTIONS_SKIPPED skipped)"
fi

echo ""
echo "✅ Sync complete for: $PROJECT_ROOT"
