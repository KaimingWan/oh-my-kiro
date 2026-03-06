#!/bin/bash
# enforce-ov-first.sh — Block find/grep on knowledge/ when OV results exist
# If OV returned results this turn, agent must use them first, not bypass with filesystem search.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only enforce when OV returned results this turn
[ -f /tmp/omk-ov-has-results ] || exit 0

# Check if command searches knowledge directory via find/grep/ls
if echo "$CMD" | grep -qiE '(find|grep|rg|ag|ls)\b.*\bknowledge[/ ]'; then
  # Allow if it's clearly a supplementary search (contains "补搜" or similar won't help — agent writes English commands)
  # Block it
  printf '🚫 BLOCKED: OV knowledge results available — use 🔎 results first before searching filesystem. See AGENTS.md §3' >&2
  exit 2
fi

exit 0
