"""Test that context-enrichment uses OV semantic search when available."""
import json, os, socket, subprocess, threading, pytest
from pathlib import Path

PROJECT_ROOT = str(Path(__file__).resolve().parent.parent)
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
            except:
                break
    t = threading.Thread(target=serve, daemon=True)
    t.start()
    yield srv
    srv.close()
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

def test_enrichment_calls_ov_search(mock_ov_search, tmp_path):
    """When OV daemon is available, context-enrichment injects semantic results."""
    overlay = tmp_path / ".omcc-overlay.json"
    overlay.write_text(json.dumps({"knowledge_backend": "openviking"}))
    ws_hash = subprocess.run(
        ["bash", "-c", f"echo '{tmp_path}' | shasum | cut -c1-8"],
        capture_output=True, text=True
    ).stdout.strip()
    Path(f"/tmp/ctx-enrich-{ws_hash}.ts").unlink(missing_ok=True)

    env = os.environ.copy()
    env["OV_SOCKET"] = SOCKET_PATH
    inp = json.dumps({"prompt": "how to configure local storage backend"})
    r = subprocess.run(
        ["bash", os.path.join(PROJECT_ROOT, "hooks/feedback/context-enrichment.sh")],
        input=inp, capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    assert "\U0001f50e" in r.stdout or "StorageConfig" in r.stdout

def test_enrichment_fallback_no_ov(tmp_path):
    """When OV daemon is NOT available, context-enrichment still works (exit 0)."""
    ws_hash = subprocess.run(
        ["bash", "-c", f"echo '{tmp_path}' | shasum | cut -c1-8"],
        capture_output=True, text=True
    ).stdout.strip()
    Path(f"/tmp/ctx-enrich-{ws_hash}.ts").unlink(missing_ok=True)

    env = os.environ.copy()
    env["OV_SOCKET"] = "/tmp/nonexistent-ov.sock"
    inp = json.dumps({"prompt": "hello"})
    r = subprocess.run(
        ["bash", os.path.join(PROJECT_ROOT, "hooks/feedback/context-enrichment.sh")],
        input=inp, capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=10
    )
    assert r.returncode == 0
