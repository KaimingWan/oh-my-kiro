#!/usr/bin/env python3
"""OpenViking daemon — hooks 通过 socket 调用，避免重复初始化"""
import json
import os
import sys
import socket
import threading

# Configure OpenViking BEFORE importing (singleton pattern)
# Priority: OLLAMA > OPENAI > AZURE
use_ollama = os.environ.get("OV_EMBEDDING_PROVIDER", "").lower() == "ollama" or os.environ.get("OLLAMA_EMBEDDING_MODEL")

if use_ollama:
    model = os.environ.get("OLLAMA_EMBEDDING_MODEL", "qwen3-embedding:latest")
    base = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
    dim = os.environ.get("OLLAMA_EMBEDDING_DIMENSION", "4096")
    os.environ['OPENVIKING_EMBEDDING_DENSE_PROVIDER'] = 'openai'
    os.environ['OPENVIKING_EMBEDDING_DENSE_MODEL'] = model
    os.environ['OPENVIKING_EMBEDDING_DENSE_DIMENSION'] = dim
    os.environ['OPENVIKING_EMBEDDING_DENSE_API_KEY'] = 'ollama'  # ollama doesn't need a real key
    os.environ['OPENVIKING_EMBEDDING_DENSE_BASE_URL'] = f"{base}/v1/"
    print(f"Using Ollama embedding: {model} (dim={dim})", flush=True)
else:
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("OPENVIKING_EMBEDDING_DENSE_API_KEY") or os.environ.get("AZURE_OPENAI_API_KEY")
    if not api_key:
        print("Error: Set OV_EMBEDDING_PROVIDER=ollama or provide OPENAI_API_KEY", file=sys.stderr)
        sys.exit(1)

    base_url = os.environ.get("OPENAI_BASE_URL") or os.environ.get("OPENVIKING_EMBEDDING_DENSE_BASE_URL")
    if not base_url and os.environ.get("AZURE_OPENAI_API_KEY"):
        base_url = "https://o3-use.openai.azure.com/openai/v1/"

    os.environ['OPENVIKING_EMBEDDING_DENSE_PROVIDER'] = 'openai'
    os.environ['OPENVIKING_EMBEDDING_DENSE_MODEL'] = 'text-embedding-3-large'
    os.environ['OPENVIKING_EMBEDDING_DENSE_DIMENSION'] = '3072'
    os.environ['OPENVIKING_EMBEDDING_DENSE_API_KEY'] = api_key
    if base_url:
        os.environ['OPENVIKING_EMBEDDING_DENSE_BASE_URL'] = base_url

try:
    from openviking import SyncOpenViking
except ImportError:
    print("Error: openviking not installed. Run: pip install openviking", file=sys.stderr)
    sys.exit(1)

SOCKET_PATH = "/tmp/omcc-ov.sock"
ov = None

def handle(conn):
    data = conn.recv(65536).decode()
    req = json.loads(data)
    cmd = req["cmd"]
    try:
        if cmd == "search":
            result = ov.search(req["query"], limit=req.get("limit", 3),
                               score_threshold=req.get("threshold", 0.3))
            out = []
            for r in result.resources[:req.get("limit", 3)]:
                text = r.abstract or r.uri
                out.append(f"[{r.score:.2f}] {r.uri}: {text[:120]}")
            conn.sendall(json.dumps({"ok": True, "results": out}).encode())
        elif cmd == "find":
            results = ov.find(req["query"], limit=req.get("limit", 5))
            conn.sendall(json.dumps({"ok": True, "results": [str(r)[:200] for r in results]}).encode())
        elif cmd == "add_resource":
            ov.add_resource(req["path"], reason=req.get("reason", ""))
            conn.sendall(json.dumps({"ok": True}).encode())
        elif cmd == "session_summary":
            s = ov.session(req.get("session_id"))
            s.load()
            conn.sendall(json.dumps({"ok": True, "summary": s.summary or ""}).encode())
        elif cmd == "session_commit":
            s = ov.session(req.get("session_id"))
            s.add_message(req.get("message", ""))
            s.commit()
            conn.sendall(json.dumps({"ok": True}).encode())
        elif cmd == "overview":
            text = ov.overview(req["uri"])
            conn.sendall(json.dumps({"ok": True, "text": text}).encode())
        elif cmd == "health":
            conn.sendall(json.dumps({"ok": ov.is_healthy()}).encode())
        else:
            conn.sendall(json.dumps({"ok": False, "error": f"unknown cmd: {cmd}"}).encode())
    except Exception as e:
        conn.sendall(json.dumps({"ok": False, "error": str(e)}).encode())
    conn.close()

def main():
    global ov
    data_dir = os.environ.get("OV_DATA_DIR", os.path.join(os.getcwd(), "data/openviking"))
    ov = SyncOpenViking(path=data_dir)
    ov.initialize()
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    srv.listen(5)
    print(f"ov-daemon listening on {SOCKET_PATH}", flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()

if __name__ == "__main__":
    main()
