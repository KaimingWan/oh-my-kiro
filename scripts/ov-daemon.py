#!/usr/bin/env python3
"""OpenViking daemon — hooks 通过 socket 调用，避免重复初始化"""
import json
import os
import sys
import socket
import threading

# Configure OpenViking BEFORE importing (singleton pattern)
api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("OPENVIKING_EMBEDDING_DENSE_API_KEY")
if not api_key:
    print("Error: OPENAI_API_KEY environment variable required", file=sys.stderr)
    print("Set it with: export OPENAI_API_KEY=your-key-here", file=sys.stderr)
    sys.exit(1)

os.environ['OPENVIKING_EMBEDDING_DENSE_PROVIDER'] = 'openai'
os.environ['OPENVIKING_EMBEDDING_DENSE_MODEL'] = 'text-embedding-3-large'
os.environ['OPENVIKING_EMBEDDING_DENSE_DIMENSION'] = '3072'
os.environ['OPENVIKING_EMBEDDING_DENSE_API_KEY'] = api_key

try:
    from openviking import SyncOpenViking, StorageConfig
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
            results = ov.search(req["query"], limit=req.get("limit", 3),
                                score_threshold=req.get("threshold", 0.5))
            # 返回 L0 摘要（省 token）
            out = [ov.abstract(r["uri"]) if "uri" in r else str(r)[:120] for r in results]
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
    storage = StorageConfig(provider="local", path=data_dir)
    ov = SyncOpenViking(path=data_dir, storage=storage)
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
