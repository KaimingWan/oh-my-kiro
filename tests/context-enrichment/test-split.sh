#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PASS=0; FAIL=0
t() {
  local desc="$1"; shift
  if (set +o pipefail; eval "$@") >/dev/null 2>&1; then echo "PASS: $desc"; PASS=$((PASS+1))
  else echo "FAIL: $desc"; FAIL=$((FAIL+1)); fi
}
t "correction-detect.sh exists" "test -x hooks/feedback/correction-detect.sh"
t "session-init.sh exists" "test -x hooks/feedback/session-init.sh"
t "correction detected" "echo '{\"prompt\":\"你错了\"}' | bash hooks/feedback/correction-detect.sh 2>&1 | grep -q CORRECTION"
t "research reminder works" "echo '{\"prompt\":\"调研一下\"}' | bash hooks/feedback/context-enrichment.sh 2>&1 | grep -q Research"
t "correction moved out" "! grep -q 'CORRECTION DETECTED' hooks/feedback/context-enrichment.sh"
t "rules injection moved out" "! grep -q 'inject_rules' hooks/feedback/context-enrichment.sh"
t "English correction detected" "echo '{\"prompt\":\"you are wrong\"}' | bash hooks/feedback/correction-detect.sh 2>&1 | grep -q CORRECTION"
t "non-correction no trigger" "! echo '{\"prompt\":\"hello world\"}' | bash hooks/feedback/correction-detect.sh 2>&1 | grep -q CORRECTION"
echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
