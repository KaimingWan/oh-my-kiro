#!/bin/bash
# session-init.sh — Session initialization (once per session)
# Cold-start: promoted episode cleanup, promotion reminder
# Rules injection moved to context-enrichment.sh (per-message, keyword-matched)

INPUT=$(cat)
USER_MSG=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

source "$(dirname "$0")/../_lib/common.sh" 2>/dev/null || true
LESSONS_FLAG="/tmp/lessons-injected-$(ws_hash).flag"
[ -f "$LESSONS_FLAG" ] && exit 0

# Episode cleanup: remove promoted episodes (cold-start fallback)
if [ -f "knowledge/episodes.md" ]; then
  PROMOTED_COUNT=$(grep -c '| promoted |' "knowledge/episodes.md" 2>/dev/null || true)
  if [ "${PROMOTED_COUNT:-0}" -gt 0 ]; then
    grep -v '| promoted |' "knowledge/episodes.md" > /tmp/episodes-clean.tmp && mv /tmp/episodes-clean.tmp "knowledge/episodes.md"
  fi
fi

# Promotion candidate reminder
if [ -f "knowledge/episodes.md" ]; then
  PROMOTE=$(grep '| active |' "knowledge/episodes.md" 2>/dev/null | cut -d'|' -f3 | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | uniq -c | awk '$1 >= 3' | wc -l | tr -d ' ')
  [ "$PROMOTE" -gt 0 ] && echo "⬆️ $PROMOTE keyword patterns appear ≥3 times in episodes → consider promotion"
fi

# Ralph loop enforcement reminder
PLAN_POINTER="docs/plans/.active"
if [ -f "$PLAN_POINTER" ]; then
  PLAN_FILE=$(cat "$PLAN_POINTER" | tr -d '[:space:]')
  if [ -f "$PLAN_FILE" ]; then
    UNCHECKED=$(awk '/^## Checklist/{found=1;buf="";next} found && /^## /{found=0} found{buf=buf"\n"$0} END{print buf}' "$PLAN_FILE" 2>/dev/null | grep -c '^\- \[ \]' || true)
    if [ "${UNCHECKED:-0}" -gt 0 ]; then
      echo "⚠️ Active plan has $UNCHECKED unchecked items. 执行命令: python3 scripts/ralph_loop.py — 不要手动执行 task。"
    fi
  fi
fi

# OV daemon cold-start + knowledge sync
source "$(dirname "$0")/../_lib/ov-init.sh" 2>/dev/null || true
if ! ov_init 2>/dev/null; then
  # Daemon not running — try to start it
  if _ov_check_overlay 2>/dev/null; then
    python3 scripts/ov-daemon.py &>/dev/null &
    for _i in 1 2 3; do
      sleep 1
      [ -S "$OV_SOCKET" ] && break
    done
    ov_init 2>/dev/null || true
  fi
fi
if [ "$OV_AVAILABLE" = "1" ]; then
  for _f in knowledge/*.md; do
    [ -f "$_f" ] && ov_add "$_f" "session-init sync" 2>/dev/null || true
  done
  # Index lesson scenario files if they exist
  for _f in knowledge/lesson-scenarios/lesson-scenario-*.md; do
    [ -f "$_f" ] && ov_add "$_f" "lesson-scenario sync" 2>/dev/null || true
  done
else
  _ov_check_overlay 2>/dev/null && echo "⚠️ OV daemon unavailable at session start — knowledge sync skipped"
fi

touch "$LESSONS_FLAG"
exit 0
