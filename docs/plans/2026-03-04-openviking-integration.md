# OpenViking Knowledge Integration

**Goal:** Make OpenViking actually power OMCC's knowledge recall and capture — semantic search for recall (context-enrichment), auto-indexing for capture (auto-capture + post-write), fix daemon init, remove socat dependency.
**Non-Goals:** Replacing episodes.md/rules.md file storage. Changing distill.sh promotion logic. Rewriting ov-daemon architecture. Adding new OV API commands.
**Architecture:** OpenViking as semantic overlay on existing file-based knowledge. OV available → semantic search + auto-index. OV unavailable → graceful fallback to existing grep. Communication via Python socket (no socat). Daemon init fixed with proper StorageConfig + correct embedding model.
**Tech Stack:** Python 3, bash, existing hooks framework
**Work Dir:** `.`

## Review

### Round 1 (4 reviewers, all REQUEST CHANGES)

**Accepted findings:**
- P0: Python socket client in ov_call must include socket.settimeout(3) to prevent indefinite hangs when daemon is unresponsive

**Rejected findings:**
- ~~"daemon initialization missing StorageConfig"~~ — This is exactly what Task 1 implements, not a plan gap
- ~~"daemon uses wrong model"~~ — Same, Task 1's implementation content
- ~~"Verify command #5 inverted logic"~~ — Reviewer misread; plan already has correct `grep -q large && ! grep -q small`
- ~~"daemon error paths untested"~~ — Out of scope (Non-Goals: not rewriting daemon architecture); daemon error paths have stderr+exit(1)
- ~~"post-write.sh lint/test untested"~~ — Existing functionality already tested; plan only adds OV indexing

## Tasks

### Task 1: Fix ov-daemon.py initialization + remove socat from ov-init.sh

**Files:**
- Modify: `scripts/ov-daemon.py`
- Modify: `hooks/_lib/ov-init.sh`
- Modify: `tools/validate-project.sh`
- Test: `tests/test_ov_client.py`

**Step 1: Write failing test**

```python
# tests/test_ov_client.py
"""Unit tests for ov-init.sh Python socket client (no socat dependency)."""
import json, os, socket, threading, pytest
from pathlib import Path

SOCKET_PATH = "/tmp/omcc-ov-test.sock"

@pytest.fixture
def mock_ov_server():
    """Minimal mock OV daemon for testing client calls."""
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    srv.listen(1)
    responses = []
    def serve():
        conn, _ = srv.accept()
        data = json.loads(conn.recv(65536).decode())
        responses.append(data)
        if data["cmd"] == "health":
            conn.sendall(json.dumps({"ok": True}).encode())
        elif data["cmd"] == "search":
            conn.sendall(json.dumps({"ok": True, "results": ["test result"]}).encode())
        elif data["cmd"] == "add_resource":
            conn.sendall(json.dumps({"ok": True}).encode())
        conn.close()
    t = threading.Thread(target=serve, daemon=True)
    t.start()
    yield srv, responses
    srv.close()
    os.unlink(SOCKET_PATH) if os.path.exists(SOCKET_PATH) else None

def test_ov_call_no_socat(mock_ov_server):
    """ov_call uses python3 socket, not socat."""
    srv, responses = mock_ov_server
    import subprocess
    r = subprocess.run(
        ["bash", "-c", f'source hooks/_lib/ov-init.sh; OV_SOCKET={SOCKET_PATH}; ov_call \'{{"cmd":"health"}}\''],
        capture_output=True, text=True, timeout=5
    )
    assert '"ok"' in r.stdout
    assert responses[0]["cmd"] == "health"

def test_ov_init_sh_no_socat():
    """ov-init.sh must not contain 'socat'."""
    content = Path("hooks/_lib/ov-init.sh").read_text()
    assert "socat" not in content

def test_validate_no_socat_warning():
    """validate-project.sh must not warn about socat."""
    content = Path("tools/validate-project.sh").read_text()
    assert "socat" not in content

def test_daemon_has_storage_config():
    """ov-daemon.py must use StorageConfig for local backend."""
    content = Path("scripts/ov-daemon.py").read_text()
    assert "StorageConfig" in content

def test_daemon_uses_large_model():
    """ov-daemon.py must use text-embedding-3-large, not small."""
    content = Path("scripts/ov-daemon.py").read_text()
    assert "text-embedding-3-large" in content
    assert "text-embedding-3-small" not in content
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/test_ov_client.py -v`
Expected: FAIL (socat still in ov-init.sh, daemon uses small model, no StorageConfig)

**Step 3: Implement**

1. `hooks/_lib/ov-init.sh`: Replace socat calls with `python3 -c "import socket,json; ..."` one-liner
2. `scripts/ov-daemon.py`: Add StorageConfig import + config param to SyncOpenViking init. Change model to text-embedding-3-large. Add OPENVIKING_EMBEDDING_DENSE_DIMENSION=3072.
3. `tools/validate-project.sh`: Remove socat warning (W7)

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/test_ov_client.py -v`
Expected: PASS

**Step 5: Commit**
`feat: fix ov-daemon init (StorageConfig + large model) + remove socat dependency`

### Task 2: Semantic recall in context-enrichment.sh

**Files:**
- Modify: `hooks/feedback/context-enrichment.sh`
- Test: `tests/test_ov_recall.py`

**Step 1: Write failing test**

```python
# tests/test_ov_recall.py
"""Test that context-enrichment uses OV semantic search when available."""
import json, os, socket, subprocess, threading, pytest
from pathlib import Path

SOCKET_PATH = "/tmp/omcc-ov-test-recall.sock"

@pytest.fixture
def mock_ov_search():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    srv.listen(2)
    def serve():
        for _ in range(2):
            try:
                conn, _ = srv.accept()
                data = json.loads(conn.recv(65536).decode())
                if data["cmd"] == "health":
                    conn.sendall(json.dumps({"ok": True}).encode())
                elif data["cmd"] == "search":
                    conn.sendall(json.dumps({"ok": True, "results": [
                        "Episode: use StorageConfig for local backend"
                    ]}).encode())
                conn.close()
            except: break
    t = threading.Thread(target=serve, daemon=True)
    t.start()
    yield srv
    srv.close()
    os.unlink(SOCKET_PATH) if os.path.exists(SOCKET_PATH) else None

def test_enrichment_calls_ov_search(mock_ov_search, tmp_path):
    """When OV daemon is available, context-enrichment injects semantic results."""
    overlay = tmp_path / ".omcc-overlay.json"
    overlay.write_text(json.dumps({"knowledge_backend": "openviking"}))
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", ""),
        "OV_SOCKET": SOCKET_PATH,
    }
    inp = json.dumps({"prompt": "how to configure local storage backend"})
    r = subprocess.run(
        ["bash", "hooks/feedback/context-enrichment.sh"],
        input=inp, capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    assert "🔎" in r.stdout or "semantic" in r.stdout.lower() or "StorageConfig" in r.stdout

def test_enrichment_fallback_no_ov(tmp_path):
    """When OV daemon is NOT available, context-enrichment still works (grep fallback)."""
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", ""),
        "OV_SOCKET": "/tmp/nonexistent-ov.sock",
    }
    inp = json.dumps({"prompt": "hello"})
    r = subprocess.run(
        ["bash", "hooks/feedback/context-enrichment.sh"],
        input=inp, capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    # Should not crash — exit 0
    assert r.returncode == 0
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/test_ov_recall.py -v`
Expected: FAIL (context-enrichment doesn't call OV)

**Step 3: Implement**

Add to `context-enrichment.sh` after the episode index hints section:
- Source `ov-init.sh`, call `ov_init`
- If `OV_AVAILABLE=1`, call `ov_search "$USER_MSG"` and parse JSON results
- Emit up to 3 results as `🔎 [result snippet]`
- If OV unavailable, skip silently (existing grep logic already runs)

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/test_ov_recall.py -v`
Expected: PASS

**Step 5: Commit**
`feat: semantic recall via OpenViking in context-enrichment`

### Task 3: Auto-index knowledge to OpenViking

**Files:**
- Modify: `hooks/feedback/auto-capture.sh`
- Modify: `hooks/feedback/post-write.sh`
- Test: `tests/test_ov_capture.py`

**Step 1: Write failing test**

```python
# tests/test_ov_capture.py
"""Test that auto-capture and post-write index to OV when available."""
import json, os, socket, subprocess, threading, pytest
from pathlib import Path

SOCKET_PATH = "/tmp/omcc-ov-test-capture.sock"

@pytest.fixture
def mock_ov_add():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    srv.listen(5)
    captured = []
    def serve():
        for _ in range(5):
            try:
                conn, _ = srv.accept()
                data = json.loads(conn.recv(65536).decode())
                captured.append(data)
                conn.sendall(json.dumps({"ok": True}).encode())
                conn.close()
            except: break
    t = threading.Thread(target=serve, daemon=True)
    t.start()
    yield srv, captured
    srv.close()
    os.unlink(SOCKET_PATH) if os.path.exists(SOCKET_PATH) else None

def test_auto_capture_indexes_to_ov(mock_ov_add, tmp_path):
    """After writing to episodes.md, auto-capture also calls ov_add."""
    srv, captured = mock_ov_add
    episodes = tmp_path / "knowledge" / "episodes.md"
    episodes.parent.mkdir(parents=True)
    episodes.write_text("# Episodes\n")
    rules = tmp_path / "knowledge" / "rules.md"
    rules.write_text("")
    overlay = tmp_path / ".omcc-overlay.json"
    overlay.write_text(json.dumps({"knowledge_backend": "openviking"}))
    # Copy hooks to tmp so they can find ov-init.sh
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", ""),
        "OV_SOCKET": SOCKET_PATH,
    }
    r = subprocess.run(
        ["bash", "hooks/feedback/auto-capture.sh", "必须用 StorageConfig 不要直接连 VikingDB"],
        capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    # Episode should be written
    assert "auto-captured" in r.stdout.lower() or episodes.read_text().count("|") > 2
    # OV should have received add_resource
    ov_adds = [c for c in captured if c.get("cmd") == "add_resource"]
    assert len(ov_adds) >= 1

def test_post_write_indexes_findings(mock_ov_add, tmp_path):
    """When agent writes to a findings/progress file, post-write indexes to OV."""
    srv, captured = mock_ov_add
    overlay = tmp_path / ".omcc-overlay.json"
    overlay.write_text(json.dumps({"knowledge_backend": "openviking"}))
    findings = tmp_path / "plan.findings.md"
    findings.write_text("## Findings\n- discovered pattern X")
    inp = json.dumps({
        "tool_name": "fs_write",
        "tool_input": {"file_path": str(findings)},
    })
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": os.environ.get("HOME", ""),
        "OV_SOCKET": SOCKET_PATH,
    }
    r = subprocess.run(
        ["bash", "hooks/feedback/post-write.sh"],
        input=inp, capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    ov_adds = [c for c in captured if c.get("cmd") == "add_resource"]
    assert len(ov_adds) >= 1
```

**Step 2: Run test — verify it fails**
Run: `python3 -m pytest tests/test_ov_capture.py -v`
Expected: FAIL

**Step 3: Implement**

1. `auto-capture.sh`: After writing to episodes.md, source ov-init.sh + ov_init. If OV_AVAILABLE, call `ov_add "$EPISODES" "episode: $SUMMARY"`.
2. `post-write.sh`: After lint/test, check if written file matches `*.findings.md` or `*.progress.md` or `knowledge/*.md`. If so, source ov-init.sh + ov_init. If OV_AVAILABLE, call `ov_add "$FILE" "knowledge update"`.

**Step 4: Run test — verify it passes**
Run: `python3 -m pytest tests/test_ov_capture.py -v`
Expected: PASS

**Step 5: Commit**
`feat: auto-index episodes and findings to OpenViking`

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## Checklist

- [x] ov-init.sh contains no socat references | `! grep -q socat hooks/_lib/ov-init.sh`
- [x] ov-init.sh ov_call works via python3 socket | `python3 -m pytest tests/test_ov_client.py::test_ov_call_no_socat -v`
- [x] validate-project.sh has no socat warning | `! grep -q socat tools/validate-project.sh`
- [x] ov-daemon.py uses StorageConfig | `grep -q StorageConfig scripts/ov-daemon.py`
- [x] ov-daemon.py uses text-embedding-3-large | `grep -q 'text-embedding-3-large' scripts/ov-daemon.py && ! grep -q 'text-embedding-3-small' scripts/ov-daemon.py`
- [x] context-enrichment.sh calls ov_search when OV available | `python3 -m pytest tests/test_ov_recall.py::test_enrichment_calls_ov_search -v`
- [x] context-enrichment.sh fallback works without OV | `python3 -m pytest tests/test_ov_recall.py::test_enrichment_fallback_no_ov -v`
- [ ] auto-capture.sh indexes to OV after episode write | `python3 -m pytest tests/test_ov_capture.py::test_auto_capture_indexes_to_ov -v`
- [ ] post-write.sh indexes findings/progress to OV | `python3 -m pytest tests/test_ov_capture.py::test_post_write_indexes_findings -v`
