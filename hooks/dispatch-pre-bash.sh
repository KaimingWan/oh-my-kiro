#!/bin/bash
# dispatch-pre-bash.sh — PreToolUse[execute_bash] dispatcher
# Calls sub-hooks in order, fail-fast on first block (exit 2).
# Global output budget: printf '%.200s' (bash 3.2 safe, no ${var:0:200}).
# Env vars:
#   SKIP_GATE=1 — skip gate hooks (security only, for subagents)
#   INCLUDE_REGRESSION=1 — include require-regression.sh (for pilot)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)

# Sub-hooks in order
HOOKS=(
    "$SCRIPT_DIR/security/block-dangerous.sh"
    "$SCRIPT_DIR/security/block-secrets.sh"
    "$SCRIPT_DIR/security/block-sed-json.sh"
    "$SCRIPT_DIR/security/block-outside-workspace.sh"
)

if [ "${SKIP_GATE:-0}" != "1" ]; then
    HOOKS+=(
        "$SCRIPT_DIR/gate/enforce-ralph-loop.sh"
        "$SCRIPT_DIR/gate/enforce-ov-first.sh"
    )
    if [ "${INCLUDE_REGRESSION:-0}" = "1" ]; then
        HOOKS+=(
            "$SCRIPT_DIR/gate/require-regression.sh"
        )
    fi
fi

for hook in "${HOOKS[@]}"; do
    [ -f "$hook" ] || continue
    stderr=$(echo "$INPUT" | bash "$hook" 2>&1 >/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%.200s' "$stderr" >&2
        exit "$rc"
    fi
done

exit 0
