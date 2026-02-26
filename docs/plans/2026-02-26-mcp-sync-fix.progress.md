# MCP Sync Fix — Progress Log

## Iteration 1 — 2026-02-26T13:25

- **Task:** Environment fix + implement all 5 checklist items (mcp.json merge, uvx migration, tests)
- **Files changed:**
  - `.kiro/rules/enforcement.md` — registered `enforce-work-dir.sh` hook (env fix)
  - `.kiro/settings/mcp.json` — changed `o` server from `python3` to `uvx`
  - `tools/sync-omcc.sh` — Step 3.9: copy-if-absent → jq merge; removed Step 3.9b
  - `tests/sync-omcc/test_mcp_sync.sh` — new test script (4 test scenarios, 6 assertions)
- **Learnings:**
  - `validate-project.sh` requires AGENTS.md with `<!-- BEGIN/END OMCC -->` markers and `knowledge/INDEX.md` — test setup must create these
  - The jq merge `.[0].mcpServers * .[1].mcpServers` correctly handles: OMCC wins for shared keys, project-custom keys preserved
  - `enforce-work-dir.sh` was on disk but unregistered in enforcement.md — caused `generate_configs.py` consistency check to fail (pre-existing issue, not from this plan)
  - Pre-write hook `gate_plan_structure` matches `docs/plans/*.progress.md` — should exclude non-plan files (noted as pre-existing bug)
- **Status:** done
