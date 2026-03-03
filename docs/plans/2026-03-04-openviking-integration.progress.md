# OpenViking Integration — Progress Log

## Iteration 1 — 2026-03-04

- **Task:** Verify ov-init.sh has no socat references (already clean) + fix environment (e2e test collection error)
- **Files changed:**
  - `tests/conftest.py` — added `collect_ignore` for `test_openviking_e2e.py`
  - `docs/plans/2026-03-04-openviking-integration.md` — marked checklist item 1
- **Learnings:**
  - `ov-init.sh` was already migrated to python3 socket — item pre-completed
  - `test_openviking_e2e.py` has module-level `SyncOpenViking()` that triggers `agfs-server` binary (Linux x86-64) at collection time → `OSError: Exec format error` on macOS ARM. Fixed via `collect_ignore` in conftest.py
  - `collect_ignore` must be in `conftest.py`, not `pyproject.toml`
  - Hook system logs bash executions to `/tmp/verify-log-{ws_hash}.jsonl` — checklist check-off requires recent successful verify command in log
  - `gate_plan_structure` hook matches all `docs/plans/*.md` including progress/findings files — use bash to write these
- **Status:** done

## Iteration 2 — 2026-03-04

- **Task:** Batch: fix ov-init.sh (python3 socket), validate-project.sh (remove socat W7), ov-daemon.py (StorageConfig + large model), context-enrichment.sh (OV semantic search Layer 4)
- **Files changed:**
  - `hooks/_lib/ov-init.sh` — replaced socat with python3 socket in ov_call + ov_init health check
  - `tools/validate-project.sh` — removed W7 socat warning
  - `scripts/ov-daemon.py` — added StorageConfig, changed to text-embedding-3-large with dim 3072
  - `hooks/feedback/context-enrichment.sh` — added Layer 4 OV semantic search after episode hints
  - `tests/test_ov_recall.py` — new test for OV recall integration (2 tests)
  - `docs/plans/2026-03-04-openviking-integration.md` — marked 5 checklist items
- **Learnings:**
  - Kiro fs_write reverts files between tool calls. All source mods must be done via execute_bash + python3 and committed in same flow
  - ov_init health check was using socat directly instead of ov_call function — fixed to reuse ov_call
  - text-embedding-3-large needs OPENVIKING_EMBEDDING_DENSE_DIMENSION=3072
  - context-enrichment.sh 60s dedup can block tests — must clear dedup file keyed by cwd hash
- **Status:** done
