#!/bin/bash
# block-outside-workspace.sh — PreToolUse[fs_write + execute_bash]
# Blocks file writes outside the workspace boundary.
source "$(dirname "$0")/../_lib/common.sh"
if ! source "$(dirname "$0")/../_lib/block-recovery.sh" 2>/dev/null; then
  hook_block_with_recovery() { hook_block "$1"; }
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Determine workspace root (fail-closed: if detection fails, block all writes)
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
if [ -z "$WORKSPACE" ] || [ "$WORKSPACE" = "/" ]; then
  hook_block "🚫 BLOCKED: Cannot determine workspace root. Refusing all writes for safety."
fi

# Allow sibling projects: parent of workspace
WORKSPACE_PARENT=$(dirname "$WORKSPACE")

case "$TOOL_NAME" in
  fs_write|Write|Edit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
    [ -z "$FILE" ] && exit 0

    # Expand ~ and $HOME
    FILE=$(echo "$FILE" | sed "s|^~|$HOME|; s|\\\$HOME|$HOME|g")

    # Resolve to absolute path (handle both existing and new files)
    if [ -e "$FILE" ]; then
      RESOLVED=$(realpath "$FILE" 2>/dev/null || echo "$FILE")
    elif [ -e "$(dirname "$FILE")" ]; then
      RESOLVED="$(realpath "$(dirname "$FILE")" 2>/dev/null)/$(basename "$FILE")"
    else
      # Parent doesn't exist — resolve relative to PWD, collapse ../
      case "$FILE" in
        /*) RESOLVED="$FILE" ;;
        *)  RESOLVED="$(pwd)/$FILE" ;;
      esac
      RESOLVED=$(python3 -c "import os; print(os.path.normpath('$RESOLVED'))" 2>/dev/null || echo "$RESOLVED")
    fi

    case "$RESOLVED" in
      "$WORKSPACE_PARENT"/*) exit 0 ;;
    esac

    hook_block_with_recovery "🚫 BLOCKED: Write outside workspace parent ($RESOLVED). Allowed: $WORKSPACE_PARENT/*" "$FILE"
    ;;

  execute_bash|Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    [ -z "$CMD" ] && exit 0

    # Patterns that indicate writing outside workspace
    # Covers: redirect (> >>), tee, cp, mv, install, ln, tar -C
    OUTSIDE_WRITE_PATTERNS=(
      '>+\s*/etc/'
      '>+\s*/usr/'
      '>+\s*/var/'
      '>+\s*/opt/'
      '>+\s*\$HOME/'
      'tee\s+(-a\s+)?(/etc/|/usr/|/var/|~/|~/.|\$HOME/)'
      '\b(cp|mv|install)\b.*\s+(/etc/|/usr/|/var/|~/|~/.|\$HOME/)'
      '\bln\b.*\s+(/etc/|/usr/|/var/|~/|~/.|\$HOME/)'
      '\btar\b.*-C\s*(/etc/|/usr/|/var/|~/|\$HOME/)'
    )

    for pattern in "${OUTSIDE_WRITE_PATTERNS[@]}"; do
      if echo "$CMD" | grep -qiE "$pattern"; then
        hook_block_with_recovery "🚫 BLOCKED: Bash writes outside workspace (matched: $pattern). Use paths inside: $WORKSPACE/" "$CMD"
      fi
    done
    ;;
esac

exit 0
