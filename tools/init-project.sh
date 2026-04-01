#!/bin/bash
# Initialize a new project with oh-my-kiro framework
# Usage: ./init-project.sh /path/to/project [project-name] [--type coding|gtm] [--knowledge file|openviking]
#
# Resilient version: skips files that already exist, guards every copy,
# and doesn't hard-fail on optional template files.

set -e

# ── Argument parsing ─────────────────────────────────────────────────────────
TARGET=""
PROJECT_NAME=""
PROJECT_TYPE="coding"
KNOWLEDGE_BACKEND="file"

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      PROJECT_TYPE="${2:?--type requires an argument (coding|gtm)}"
      shift 2
      ;;
    --knowledge)
      KNOWLEDGE_BACKEND="${2:?--knowledge requires an argument (file|openviking)}"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      elif [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: $0 /path/to/project [project-name] [--type coding|gtm]" >&2
  exit 1
fi

PROJECT_NAME="${PROJECT_NAME:-$(basename "$TARGET")}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Validate --type value
case "$PROJECT_TYPE" in
  coding|gtm) ;;
  *)
    echo "Unknown --type: $PROJECT_TYPE. Valid values: coding, gtm" >&2
    exit 1
    ;;
esac

# ── Helper: copy file only if source exists and target doesn't ────────────────
safe_cp() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "  ⏭  Skipping (source missing): $src"
    return 0
  fi
  if [ -e "$dst" ]; then
    echo "  ⏭  Skipping (already exists): $dst"
    return 0
  fi
  cp "$src" "$dst"
}

# ── Helper: copy directory only if source exists and target doesn't ───────────
safe_cp_r() {
  local src="$1" dst="$2"
  if [ ! -d "$src" ]; then
    echo "  ⏭  Skipping dir (source missing): $src"
    return 0
  fi
  if [ -d "$dst" ]; then
    echo "  ⏭  Skipping dir (already exists): $dst"
    return 0
  fi
  # -RP: don't follow symlinks (avoids cycles from self-referencing links)
  cp -RP "$src" "$dst"
}

# ── Helper: create symlink only if it doesn't already exist ───────────────────
safe_ln() {
  local target="$1" link="$2"
  if [ -L "$link" ] || [ -e "$link" ]; then
    echo "  ⏭  Skipping link (already exists): $link"
    return 0
  fi
  ln -sf "$target" "$link"
}

# ── Helper: sed in-place (macOS + Linux compatible) ───────────────────────────
portable_sed_i() {
  local pattern="$1" file="$2"
  sed -i '' "$pattern" "$file" 2>/dev/null || sed -i "$pattern" "$file"
}

echo "🚀 Initializing: $TARGET ($PROJECT_NAME) [type=$PROJECT_TYPE]"

# ── Create directory structure ────────────────────────────────────────────────
mkdir -p "$TARGET"/{.kiro/rules,.kiro/agents,knowledge/product,docs/{designs,plans,research,decisions},tools,templates}

# ── Copy CLAUDE.md (optional — only if template has one) ─────────────────────
if [ -f "$TEMPLATE_DIR/CLAUDE.md" ]; then
  if safe_cp "$TEMPLATE_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"; then
    [ -f "$TARGET/CLAUDE.md" ] && portable_sed_i "s/\[Project Name\]/$PROJECT_NAME/g" "$TARGET/CLAUDE.md"
  fi
else
  echo "  ℹ  No CLAUDE.md in template — skipping"
fi

# ── Assemble AGENTS.md ────────────────────────────────────────────────────────
if [ -f "$TARGET/AGENTS.md" ]; then
  echo "  ⏭  Skipping AGENTS.md (already exists)"
else
  SECTIONS_DIR="$TEMPLATE_DIR/templates/agents-sections"
  TYPES_DIR="$TEMPLATE_DIR/templates/agents-types"
  TYPE_TEMPLATE="$TYPES_DIR/$PROJECT_TYPE.md"

  if [ -d "$SECTIONS_DIR" ] && [ -f "$TYPE_TEMPLATE" ]; then
    SECTIONS_LINE=$(grep "OMK SECTIONS:" "$TYPE_TEMPLATE" | head -1)
    SECTION_NAMES=$(echo "$SECTIONS_LINE" | sed 's/.*OMK SECTIONS: *//;s/ *-->.*//')
    grep -v "OMK SECTIONS:" "$TYPE_TEMPLATE" > "$TARGET/AGENTS.md"
    for section in $SECTION_NAMES; do
      section_file="$SECTIONS_DIR/$section.md"
      if [ -f "$section_file" ]; then
        echo "" >> "$TARGET/AGENTS.md"
        cat "$section_file" >> "$TARGET/AGENTS.md"
      fi
    done
    portable_sed_i "s/\[Project Name\]/$PROJECT_NAME/g" "$TARGET/AGENTS.md"
  elif [ -f "$TEMPLATE_DIR/AGENTS.md" ]; then
    cp "$TEMPLATE_DIR/AGENTS.md" "$TARGET/AGENTS.md"
    portable_sed_i "s/\[Project Name\]/$PROJECT_NAME/g" "$TARGET/AGENTS.md"
  else
    echo "  ⚠️  No AGENTS.md template found — skipping"
  fi
fi

# ── Copy framework files ──────────────────────────────────────────────────────

# .kiro/settings — handle both settings.json (legacy) and settings/ dir
if [ -f "$TEMPLATE_DIR/.kiro/settings.json" ]; then
  safe_cp "$TEMPLATE_DIR/.kiro/settings.json" "$TARGET/.kiro/settings.json"
elif [ -d "$TEMPLATE_DIR/.kiro/settings" ]; then
  mkdir -p "$TARGET/.kiro/settings"
  for f in "$TEMPLATE_DIR/.kiro/settings/"*; do
    [ -f "$f" ] && safe_cp "$f" "$TARGET/.kiro/settings/$(basename "$f")"
  done
else
  echo "  ℹ  No .kiro/settings found in template — skipping"
fi

# .kiro/rules/
if [ -d "$TEMPLATE_DIR/.kiro/rules" ]; then
  for f in "$TEMPLATE_DIR/.kiro/rules/"*.md; do
    [ -f "$f" ] && safe_cp "$f" "$TARGET/.kiro/rules/$(basename "$f")"
  done
fi

# Hooks
safe_cp_r "$TEMPLATE_DIR/hooks" "$TARGET/hooks"
safe_ln ../hooks "$TARGET/.kiro/hooks"

# .kiro/agents/
if [ -d "$TEMPLATE_DIR/.kiro/agents" ]; then
  for f in "$TEMPLATE_DIR/.kiro/agents/"*.json; do
    [ -f "$f" ] && safe_cp "$f" "$TARGET/.kiro/agents/$(basename "$f")"
  done
fi

# Knowledge
safe_cp "$TEMPLATE_DIR/knowledge/INDEX.md" "$TARGET/knowledge/INDEX.md"
for tmpl in episodes.md rules.md; do
  if [ -f "$TEMPLATE_DIR/templates/knowledge/$tmpl" ]; then
    safe_cp "$TEMPLATE_DIR/templates/knowledge/$tmpl" "$TARGET/knowledge/$tmpl"
  fi
done
if [ -d "$TEMPLATE_DIR/knowledge/product" ]; then
  cp -rn "$TEMPLATE_DIR/knowledge/product/." "$TARGET/knowledge/product/" 2>/dev/null || true
fi

# Docs
safe_cp "$TEMPLATE_DIR/docs/INDEX.md" "$TARGET/docs/INDEX.md"
for d in designs plans research decisions; do
  touch "$TARGET/docs/$d/.gitkeep"
done

# .gitignore
safe_cp "$TEMPLATE_DIR/.gitignore" "$TARGET/.gitignore"

# ── Copy skills (preserving structure, symlinked like hooks) ──────────────────
if [ -d "$TEMPLATE_DIR/skills" ]; then
  safe_cp_r "$TEMPLATE_DIR/skills" "$TARGET/skills"
  safe_ln ../skills "$TARGET/.kiro/skills"
  SKILL_COUNT=$(ls -d "$TARGET/skills/"*/ 2>/dev/null | wc -l | tr -d ' ')
  echo "📦 Skills: $SKILL_COUNT"
fi

# ── Copy commands & link to .kiro/prompts ─────────────────────────────────────
if [ -d "$TEMPLATE_DIR/commands" ]; then
  safe_cp_r "$TEMPLATE_DIR/commands" "$TARGET/commands"
  safe_ln ../commands "$TARGET/.kiro/prompts"
  echo "📦 Copied commands → .kiro/prompts"
fi

# ── Create overlay scaffolding ────────────────────────────────────────────────
if [ ! -f "$TARGET/.omk-overlay.json" ]; then
  if [ "$KNOWLEDGE_BACKEND" = "openviking" ]; then
    printf '{\n  "extra_skills": [],\n  "extra_hooks": {},\n  "knowledge_backend": "openviking",\n  "openviking": {\n    "data_dir": "data/openviking"\n  }\n}\n' > "$TARGET/.omk-overlay.json"
  else
    printf '{\n  "extra_skills": [],\n  "extra_hooks": {}\n}\n' > "$TARGET/.omk-overlay.json"
  fi
fi

mkdir -p "$TARGET/hooks/project"

# Copy EXTENSION-GUIDE.md if available
if [ -f "$TEMPLATE_DIR/docs/EXTENSION-GUIDE.md" ]; then
  safe_cp "$TEMPLATE_DIR/docs/EXTENSION-GUIDE.md" "$TARGET/docs/EXTENSION-GUIDE.md"
fi

# ── Update agent config with project name (only if jq available + file exists)
if command -v jq &>/dev/null && [ -f "$TARGET/.kiro/agents/pilot.json" ]; then
  jq --arg name "$PROJECT_NAME agent" '.description = $name' "$TARGET/.kiro/agents/pilot.json" > "$TARGET/.kiro/agents/pilot.json.tmp" && \
  mv "$TARGET/.kiro/agents/pilot.json.tmp" "$TARGET/.kiro/agents/pilot.json"
fi

echo ""
echo "✅ Done! Project initialized at: $TARGET"
echo ""
echo "📁 Structure:"
[ -f "$TARGET/CLAUDE.md" ] && echo "  CLAUDE.md              — High-frequency recall (Claude Code)"
[ -f "$TARGET/AGENTS.md" ] && echo "  AGENTS.md              — High-frequency recall (Kiro CLI) [type=$PROJECT_TYPE]"
echo "  .kiro/rules/           — Enforcement + Reference layers"
echo "  .kiro/hooks/           — Automated guardrails"
if [ -n "${SKILL_COUNT:-}" ]; then
echo "  .kiro/skills/          — $SKILL_COUNT pre-installed skills"
fi
echo "  .omk-overlay.json     — Project extension overlay (skills/hooks)"
echo "  hooks/project/         — Project-specific hooks directory"
echo "  knowledge/INDEX.md     — Knowledge routing (empty, fill it in)"
echo "  knowledge/product/     — Product map (features, constraints)"
echo "  docs/                  — Designs, plans, research, decisions"
echo "  tools/                 — Reusable scripts"
echo ""
echo "👉 Next: Edit AGENTS.md to customize your agent identity and roles"
