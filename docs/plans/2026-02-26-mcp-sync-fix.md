# MCP Sync Fix — mcp.json merge + uvx runtime

**Goal:** Fix sync-omcc.sh so MCP configs and MCP server runtime dependencies are correctly propagated to target projects, making `o/know` and `o/agent` commands work after sync.
**Non-Goals:** Adding new MCP servers; changing MCP prompt content; modifying Claude Code (`.claude/`) MCP handling; modifying generate_configs.py.
**Architecture:** Two changes in sync-omcc.sh: (1) Step 3.9 switches from copy-if-absent to jq merge for mcp.json (with copy fallback for first-time sync), (2) Step 3.9b is removed (merge in 3.9 now handles `o` server registration). The source `.kiro/settings/mcp.json` is updated to use uvx for the `o` server so the mcp dependency is auto-resolved at runtime.
**Tech Stack:** bash, jq, uvx

## Tasks

### Task 1: Update source mcp.json + fix sync merge strategy + remove redundant Step 3.9b

**Files:**
- Modify: `.kiro/settings/mcp.json` (source of truth — change `o` server to uvx)
- Modify: `tools/sync-omcc.sh` (Step 3.9: copy-if-absent → jq merge; remove Step 3.9b)
- Create: `tests/sync-omcc/test_mcp_sync.sh`

**What to implement:**

1. Update `.kiro/settings/mcp.json`: change `o` server to `{"command":"uvx","args":["--with","mcp[cli]","python3","scripts/mcp-prompts.py"]}`
2. Replace `tools/sync-omcc.sh` Step 3.9 with:
   - If project mcp.json doesn't exist: `mkdir -p` the dir, copy from OMCC
   - If project mcp.json exists: `jq -s '.[0] * .[1]' "$PROJECT_MCP" "$OMCC_MCP"` — wraps mcpServers level so OMCC servers override same-key entries, project-only servers preserved. Actually the correct merge is: build a new object with `{mcpServers: (project.mcpServers + omcc.mcpServers)}` so OMCC wins for shared keys. Use: `jq -s '{"mcpServers": (.[0].mcpServers * .[1].mcpServers)}' "$PROJECT_MCP" "$OMCC_MCP"`
3. Remove Step 3.9b entirely (the standalone `o` server jq injection) — now redundant since merge handles it.

**Verify:** `bash tests/sync-omcc/test_mcp_sync.sh`

## Review

### Round 1 (4 reviewers: Goal Alignment, Verify Correctness, Technical Feasibility, Completeness)

All 4 reviewers: REQUEST CHANGES. Issues found and fixed:
1. ~~Plan assumed generate_configs.py has `o` server injection logic~~ — it doesn't. Removed generate_configs.py from modified files.
2. ~~jq -s fails when project mcp.json doesn't exist~~ — added copy fallback for first-time sync.
3. ~~Missing `.kiro/settings/` directory creation~~ — added `mkdir -p` in copy fallback path.
4. ~~Checklist item 4 tested source file not generate_configs.py output~~ — removed invalid checklist item.

### Round 2 (2 reviewers: Goal Alignment, Verify Correctness)

Both reviewers: **APPROVE**. All Round 1 issues verified as fixed.

## Checklist
- [x] mcp.json merge: OMCC servers merged into project, project-custom servers preserved | `bash tests/sync-omcc/test_mcp_sync.sh`
- [x] o server uses uvx after sync | `bash tests/sync-omcc/test_mcp_sync.sh`
- [x] existing bare-python3 o server upgraded to uvx after sync | `bash tests/sync-omcc/test_mcp_sync.sh`
- [x] first-time sync (no project mcp.json) works | `bash tests/sync-omcc/test_mcp_sync.sh`
- [x] source mcp.json updated to uvx | `jq -r '.mcpServers.o.command' .kiro/settings/mcp.json | grep -q uvx`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|
