#!/bin/bash
# Tests for mcp.json merge logic in sync-omcc.sh Step 3.9
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OMCC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$OMCC_ROOT/tools/sync-omcc.sh"

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ✅ $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

setup_project() {
  local tmp="$1"
  mkdir -p "$tmp/.kiro/settings" "$tmp/.kiro/rules" "$tmp/knowledge"
  echo '{}' > "$tmp/.omcc-overlay.json"
  # AGENTS.md with required OMCC markers
  cat > "$tmp/AGENTS.md" <<'AGENTS'
<!-- BEGIN OMCC Framework -->
<!-- END OMCC Framework -->
AGENTS
  # knowledge/INDEX.md required by validation
  echo "# Index" > "$tmp/knowledge/INDEX.md"
  cp "$OMCC_ROOT/templates/knowledge/episodes.md" "$tmp/knowledge/episodes.md" 2>/dev/null || touch "$tmp/knowledge/episodes.md"
  cp "$OMCC_ROOT/templates/knowledge/rules.md" "$tmp/knowledge/rules.md" 2>/dev/null || touch "$tmp/knowledge/rules.md"
  (cd "$tmp" && git init -q 2>/dev/null || true)
}

# ─── Test 1: Merge — OMCC servers merged, project-custom preserved ────────────
echo "Test 1: mcp.json merge preserves project-custom servers"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
setup_project "$TMP"
cat > "$TMP/.kiro/settings/mcp.json" <<'EOF'
{
  "mcpServers": {
    "my-custom": {"command": "node", "args": ["my-server.js"]},
    "o": {"command": "python3", "args": ["scripts/mcp-prompts.py"]}
  }
}
EOF

bash "$SYNC_SCRIPT" "$TMP" > /dev/null 2>&1 || true

O_CMD=$(jq -r '.mcpServers.o.command' "$TMP/.kiro/settings/mcp.json")
CUSTOM=$(jq -r '.mcpServers["my-custom"].command' "$TMP/.kiro/settings/mcp.json")
RIPGREP=$(jq -r '.mcpServers.ripgrep.command' "$TMP/.kiro/settings/mcp.json")

assert_eq "OMCC 'o' server merged (uvx)" "uvx" "$O_CMD"
assert_eq "project-custom server preserved" "node" "$CUSTOM"
assert_eq "OMCC 'ripgrep' server merged" "npx" "$RIPGREP"

# ─── Test 2: o server uses uvx after sync ─────────────────────────────────────
echo "Test 2: o server uses uvx after sync"
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP2"' EXIT
setup_project "$TMP2"
cat > "$TMP2/.kiro/settings/mcp.json" <<'EOF'
{"mcpServers": {}}
EOF

bash "$SYNC_SCRIPT" "$TMP2" > /dev/null 2>&1 || true

O_CMD2=$(jq -r '.mcpServers.o.command' "$TMP2/.kiro/settings/mcp.json")
assert_eq "o server command is uvx" "uvx" "$O_CMD2"

# ─── Test 3: existing bare-python3 o server upgraded to uvx ───────────────────
echo "Test 3: existing bare-python3 o server upgraded to uvx"
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP3"' EXIT
setup_project "$TMP3"
cat > "$TMP3/.kiro/settings/mcp.json" <<'EOF'
{
  "mcpServers": {
    "o": {"command": "python3", "args": ["scripts/mcp-prompts.py"]}
  }
}
EOF

bash "$SYNC_SCRIPT" "$TMP3" > /dev/null 2>&1 || true

O_CMD3=$(jq -r '.mcpServers.o.command' "$TMP3/.kiro/settings/mcp.json")
assert_eq "bare python3 upgraded to uvx" "uvx" "$O_CMD3"

# ─── Test 4: first-time sync (no project mcp.json) ───────────────────────────
echo "Test 4: first-time sync (no project mcp.json)"
TMP4=$(mktemp -d)
trap 'rm -rf "$TMP4"' EXIT
setup_project "$TMP4"
rm -f "$TMP4/.kiro/settings/mcp.json"

bash "$SYNC_SCRIPT" "$TMP4" > /dev/null 2>&1 || true

[ -f "$TMP4/.kiro/settings/mcp.json" ]
O_CMD4=$(jq -r '.mcpServers.o.command' "$TMP4/.kiro/settings/mcp.json")
assert_eq "mcp.json created" "uvx" "$O_CMD4"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
