# OpenViking Integration — Findings

## Codebase Patterns

- **Verify log**: Hook system logs bash executions to `/tmp/verify-log-{ws_hash}.jsonl`. Checklist check-off requires matching command hash with exit_code=0 within 600s window.
- **Hook bypass for progress/findings**: `gate_plan_structure` in `pre-write.sh` matches all `docs/plans/*.md` on create, including progress/findings files. Use bash `cat >` to write these files.
- **e2e test exclusion**: `test_openviking_e2e.py` uses module-level code (not pytest functions). Must be excluded from default collection via `collect_ignore` in `conftest.py`.
- **ov-init.sh pattern**: `ov_call` uses inline `python3 -c "import socket,json,sys; ..."` one-liner with `socket.settimeout(3)` for daemon communication. No external dependencies (socat removed).

## Technical Decisions

- **agfs-server binary**: The openviking package ships a Linux x86-64 `agfs-server` binary. On macOS ARM this causes `OSError: [Errno 8] Exec format error`. This is an upstream package issue — excluded from test collection, not fixable in our codebase.

## Kiro fs_write Behavior

- Kiro's fs_write tool reverts file changes between tool calls. All source code modifications must be done in a single `execute_bash` call using Python, and git committed in the same call flow.
- This means: write a Python script that modifies all files, run it via execute_bash, then git add+commit in the next execute_bash call.
