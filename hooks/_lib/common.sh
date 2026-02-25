#!/bin/bash
# common.sh — Shared functions for all hooks (v3)

HOOKS_DRY_RUN="${HOOKS_DRY_RUN:-false}"

hook_block() {
  if [ "$HOOKS_DRY_RUN" = "true" ]; then
    echo "⚠️ DRY RUN — would have blocked: $1" >&2
    exit 0
  fi
  echo "$1" >&2
  exit 2
}

file_mtime() {
  local f="$1"
  if [ "$(uname)" = "Darwin" ]; then
    stat -f %m "$f" 2>/dev/null || echo 0
  else
    stat -c %Y "$f" 2>/dev/null || echo 0
  fi
}

detect_test_command() {
  if [ -f "package.json" ]; then echo "npm test --silent"
  elif [ -f "Cargo.toml" ]; then echo "cargo test 2>&1"
  elif [ -f "go.mod" ]; then echo "go test ./... 2>&1"
  elif [ -f "pom.xml" ]; then echo "mvn test -q 2>&1"
  elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then echo "gradle test 2>&1"
  elif [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ] || [ -f "conftest.py" ]; then echo "python3 -m pytest 2>&1"
  elif [ -f "Makefile" ] && grep -q '^test:' Makefile 2>/dev/null; then echo "make test 2>&1"
  else echo ""; fi
}

is_source_file() {
  echo "$1" | grep -qE '\.(ts|js|py|java|rs|go|rb|swift|kt|sh|bash|zsh|yaml|yml|toml|tf|hcl)$'
}

is_test_file() {
  echo "$1" | grep -qiE '(test|spec|__test__)'
}

# Run project-specific extension for the calling hook.
# Usage: call at end of any hook script.
# Looks for hooks/project/<caller-basename>-ext.sh
run_project_extensions() {
  local caller="${1:-$(basename "${BASH_SOURCE[1]}" .sh)}"
  local ext="hooks/project/${caller}-ext.sh"
  [ -f "$ext" ] && source "$ext"
}

find_active_plan() {
  # Priority 1: explicit .active pointer
  if [ -f "docs/plans/.active" ]; then
    local ACTIVE=$(cat "docs/plans/.active" 2>/dev/null)
    [ -f "$ACTIVE" ] && echo "$ACTIVE" && return
  fi

  # Priority 2: time-window fallback
  local WINDOW="${WORKFLOW_PLAN_WINDOW:-14400}"
  local NOW=$(date +%s)
  local LATEST=""
  local LATEST_MTIME=0

  for f in docs/plans/*.md; do
    [ -f "$f" ] || continue
    local mt=$(file_mtime "$f")
    if [ $((NOW - mt)) -lt "$WINDOW" ] && [ "$mt" -gt "$LATEST_MTIME" ]; then
      LATEST="$f"
      LATEST_MTIME="$mt"
    fi
  done

  if [ -z "$LATEST" ] && [ -f ".completion-criteria.md" ]; then
    local mt=$(file_mtime ".completion-criteria.md")
    if [ $((NOW - mt)) -lt "$WINDOW" ]; then
      LATEST=".completion-criteria.md"
    fi
  fi

  echo "$LATEST"
}
