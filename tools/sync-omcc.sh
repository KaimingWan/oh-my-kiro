#!/bin/bash
# Sync a project with the latest OMCC framework
#
# Usage: sync-omcc.sh [PROJECT_ROOT]
#   PROJECT_ROOT: path to project directory (default: current directory)
#
# Steps:
#   1. Submodule update (if project uses OMCC as a submodule)
#   2. Validate project overlay (.omcc-overlay.json)
#   3. Generate agent configs (generate_configs.py --overlay)
#   4. Update AGENTS.md framework sections (BEGIN/END OMCC markers)
#
# Exit 0: success
# Exit 1: error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMCC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_ROOT="${1:-$(pwd)}"

err() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }

[ -d "$PROJECT_ROOT" ] || err "PROJECT_ROOT does not exist: $PROJECT_ROOT"

echo "🔄 Syncing OMCC for project: $PROJECT_ROOT"
echo ""

# ─── Step 1: Submodule update ─────────────────────────────────────────────────
# Only run if the project root is a git repo and has OMCC as a submodule
if [ -f "$PROJECT_ROOT/.gitmodules" ] && grep -q "oh-my-claude-code\|omcc" "$PROJECT_ROOT/.gitmodules" 2>/dev/null; then
  info "Step 1: Updating OMCC submodule..."
  (cd "$PROJECT_ROOT" && git submodule update --init --remote oh-my-claude-code 2>/dev/null || \
   git submodule update --init --remote omcc 2>/dev/null || \
   git submodule update --init --remote 2>/dev/null) || {
    echo "⚠️  Submodule update failed or not applicable, continuing..."
  }
  ok "Step 1: Submodule up to date"
else
  info "Step 1: No OMCC submodule detected, skipping submodule update"
fi

# ─── Step 2: Validate project overlay ────────────────────────────────────────
info "Step 2: Validating project overlay..."
VALIDATE_SCRIPT="$OMCC_ROOT/tools/validate-project.sh"
if [ ! -f "$VALIDATE_SCRIPT" ]; then
  err "validate-project.sh not found at: $VALIDATE_SCRIPT"
fi

if ! bash "$VALIDATE_SCRIPT" "$PROJECT_ROOT"; then
  err "Step 2: Validation failed — fix errors before syncing"
fi
ok "Step 2: Validation passed"

# ─── Step 3: Generate agent configs ──────────────────────────────────────────
info "Step 3: Generating agent configs..."
GENERATE_SCRIPT="$OMCC_ROOT/scripts/generate_configs.py"
if [ ! -f "$GENERATE_SCRIPT" ]; then
  err "generate_configs.py not found at: $GENERATE_SCRIPT"
fi

OVERLAY_FILE="$PROJECT_ROOT/.omcc-overlay.json"
GENERATE_CMD="python3 $GENERATE_SCRIPT --project-root $PROJECT_ROOT --skip-validate"
if [ -f "$OVERLAY_FILE" ]; then
  GENERATE_CMD="$GENERATE_CMD --overlay $OVERLAY_FILE"
fi

if ! eval "$GENERATE_CMD"; then
  err "Step 3: Config generation failed"
fi
ok "Step 3: Agent configs generated"

# ─── Step 3.5: Ensure commands symlink ────────────────────────────────────────
if [ -d "$OMCC_ROOT/commands" ] && [ ! -e "$PROJECT_ROOT/commands" ]; then
  ln -s .omcc/commands "$PROJECT_ROOT/commands"
  ok "Step 3.5: commands/ symlink created"
elif [ -L "$PROJECT_ROOT/commands" ]; then
  info "Step 3.5: commands/ symlink already exists"
else
  info "Step 3.5: commands/ directory exists (not a symlink), skipping"
fi

# ─── Step 3.6: Ensure .kiro/prompts → commands symlink (Kiro CLI custom commands) ─
KIRO_PROMPTS="$PROJECT_ROOT/.kiro/prompts"
if [ -d "$PROJECT_ROOT/.kiro" ] && [ -e "$PROJECT_ROOT/commands" ]; then
  if [ ! -e "$KIRO_PROMPTS" ]; then
    ln -s ../commands "$KIRO_PROMPTS"
    ok "Step 3.6: .kiro/prompts → ../commands symlink created"
  elif [ -L "$KIRO_PROMPTS" ]; then
    info "Step 3.6: .kiro/prompts symlink already exists"
  else
    info "Step 3.6: .kiro/prompts is a real directory, skipping"
  fi
else
  info "Step 3.6: .kiro/ or commands/ not found, skipping prompts symlink"
fi

# ─── Step 3.7: Ensure scripts symlink (needed for ralph_loop.py) ──────────────
if [ -d "$OMCC_ROOT/scripts" ] && [ ! -e "$PROJECT_ROOT/scripts" ]; then
  ln -s .omcc/scripts "$PROJECT_ROOT/scripts"
  ok "Step 3.7: scripts/ symlink created"
elif [ -L "$PROJECT_ROOT/scripts" ]; then
  info "Step 3.7: scripts/ symlink already exists"
elif [ -d "$PROJECT_ROOT/scripts" ]; then
  info "Step 3.7: scripts/ is a real directory, skipping"
fi

# ─── Step 3.8: Ensure docs/plans/ directory (needed for @plan/@execute) ───────
mkdir -p "$PROJECT_ROOT/docs/plans"
info "Step 3.8: docs/plans/ ensured"

# ─── Step 3.9: Sync .kiro/settings/mcp.json ──────────────────────────────────
OMCC_MCP="$OMCC_ROOT/.kiro/settings/mcp.json"
PROJECT_MCP="$PROJECT_ROOT/.kiro/settings/mcp.json"
if [ -f "$OMCC_MCP" ] && [ -d "$PROJECT_ROOT/.kiro/settings" ]; then
  if [ ! -f "$PROJECT_MCP" ]; then
    cp "$OMCC_MCP" "$PROJECT_MCP"
    ok "Step 3.9: .kiro/settings/mcp.json copied from OMCC"
  else
    info "Step 3.9: .kiro/settings/mcp.json already exists, skipping"
  fi
else
  info "Step 3.9: mcp.json source or .kiro/settings/ not found, skipping"
fi

# ─── Step 3.9b: Ensure 'o' MCP prompt server is registered ───────────────────
MCP_JSON="$PROJECT_ROOT/.kiro/settings/mcp.json"
if command -v jq &>/dev/null && [ -f "$MCP_JSON" ]; then
  if ! jq -e '.mcpServers.o' "$MCP_JSON" &>/dev/null; then
    jq '.mcpServers.o = {"command": "python3", "args": ["scripts/mcp-prompts.py"]}' "$MCP_JSON" > "${MCP_JSON}.tmp" && mv "${MCP_JSON}.tmp" "$MCP_JSON"
    ok "Step 3.9b: 'o' MCP server registered in mcp.json"
  else
    info "Step 3.9b: 'o' MCP server already in mcp.json"
  fi
fi

# ─── Step 3.10: Sync .kiro/rules/ framework files ────────────────────────────
# Copy OMCC's .kiro/rules/ files to project, skip files that already exist
# (project-customized files take precedence)
OMCC_KIRO_RULES="$OMCC_ROOT/.kiro/rules"
PROJECT_KIRO_RULES="$PROJECT_ROOT/.kiro/rules"
if [ -d "$OMCC_KIRO_RULES" ] && [ -d "$PROJECT_KIRO_RULES" ]; then
  RULES_SYNCED=0
  for rule_file in "$OMCC_KIRO_RULES"/*.md; do
    [ -f "$rule_file" ] || continue
    rule_name=$(basename "$rule_file")
    if [ ! -f "$PROJECT_KIRO_RULES/$rule_name" ]; then
      cp "$rule_file" "$PROJECT_KIRO_RULES/$rule_name"
      RULES_SYNCED=$((RULES_SYNCED + 1))
    fi
  done
  if [ "$RULES_SYNCED" -gt 0 ]; then
    ok "Step 3.10: Synced $RULES_SYNCED new .kiro/rules/ file(s) from OMCC"
  else
    info "Step 3.10: .kiro/rules/ already up to date"
  fi
else
  info "Step 3.10: .kiro/rules/ source or target not found, skipping"
fi


# ─── Step 3.11: Ensure knowledge/episodes.md and rules.md exist ───────────────
KNOWLEDGE_DIR="$PROJECT_ROOT/knowledge"
TEMPLATES_DIR="$OMCC_ROOT/templates/knowledge"
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
OMCC_AGENTS_MD="$OMCC_ROOT/AGENTS.md"

if [ ! -f "$AGENTS_MD" ]; then
  info "No AGENTS.md in project, skipping section update"
elif [ ! -f "$OMCC_AGENTS_MD" ]; then
  info "No AGENTS.md in OMCC root, skipping section update"
else
  # For each BEGIN/END OMCC section in the OMCC AGENTS.md, update matching section in project
  SECTIONS_UPDATED=0
  SECTIONS_SKIPPED=0

  # Extract section names from OMCC AGENTS.md
  while IFS= read -r section_name; do
    [ -z "$section_name" ] && continue

    # Check if project AGENTS.md has this section
    if ! grep -q "<!-- BEGIN OMCC $section_name -->" "$AGENTS_MD" 2>/dev/null; then
      SECTIONS_SKIPPED=$((SECTIONS_SKIPPED + 1))
      continue
    fi

    # Extract section content from OMCC AGENTS.md (including markers)
    OMCC_SECTION=$(awk "/<!-- BEGIN OMCC $section_name -->/,/<!-- END OMCC $section_name -->/" "$OMCC_AGENTS_MD" 2>/dev/null || true)
    if [ -z "$OMCC_SECTION" ]; then
      SECTIONS_SKIPPED=$((SECTIONS_SKIPPED + 1))
      continue
    fi

    # Create temp file for updated AGENTS.md
    TMP_AGENTS=$(mktemp)
    trap 'rm -f "$TMP_AGENTS"' EXIT

    # Replace section in project AGENTS.md using awk
    awk -v section="$section_name" -v new_content="$OMCC_SECTION" '
      /<!-- BEGIN OMCC / && index($0, "<!-- BEGIN OMCC " section " -->") > 0 {
        print new_content
        skip = 1
        next
      }
      /<!-- END OMCC / && index($0, "<!-- END OMCC " section " -->") > 0 {
        skip = 0
        next
      }
      !skip { print }
    ' "$AGENTS_MD" > "$TMP_AGENTS"

    mv "$TMP_AGENTS" "$AGENTS_MD"
    SECTIONS_UPDATED=$((SECTIONS_UPDATED + 1))
  done < <(grep -oP '(?<=<!-- BEGIN OMCC ).*(?= -->)' "$OMCC_AGENTS_MD" 2>/dev/null || true)

  ok "Step 4: AGENTS.md updated ($SECTIONS_UPDATED sections updated, $SECTIONS_SKIPPED skipped)"
fi

echo ""
echo "✅ Sync complete for: $PROJECT_ROOT"
