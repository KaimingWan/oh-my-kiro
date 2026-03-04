#!/usr/bin/env python3
"""OpenViking daemon — hooks 通过 socket 调用，避免重复初始化"""
import json
import os
import sys
import socket
import threading
import logging
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("ov-daemon")

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

# --- Gate: filter noise queries ---
_CONFIRM_WORDS = frozenset(["ok", "好", "确认", "嗯", "是的", "好的", "收到", "明白", "yes", "no", "是", "否"])

def _is_noise_query(query: str) -> bool:
    q = query.strip()
    return len(q) <= 3 or q.lower() in _CONFIRM_WORDS

def _autocut(results, min_score=0.55, max_gap=0.08):
    """Filter by min score, then cut at first large gap."""
    kept = [r for r in results if r.score >= min_score]
    if len(kept) <= 1:
        return kept
    cut = []
    for i, r in enumerate(kept):
        cut.append(r)
        if i + 1 < len(kept) and (r.score - kept[i + 1].score) > max_gap:
            break
    return cut

# --- LLM query rewrite ---
_REWRITE_PROMPT = (
    "Convert user message to a knowledge base search query for AutoMQ GTM. "
    "Strip greetings and irrelevant context. "
    "If the query mentions a competitor (Confluent, MSK, Redpanda, WarpStream, Kafka), "
    "rewrite as 'AutoMQ vs <competitor> <topic>' in English. "
    "If about a task, include what tools/knowledge needed. "
    "Output ONLY the search query in English, no explanation."
)

def rewrite_query(query: str) -> str | None:
    """Rewrite query via LLM. Returns None on failure (silent fallback)."""
    api_key = os.environ.get("AZURE_OPENAI_API_KEY")
    if not api_key:
        return None
    endpoint = "https://o3-use.openai.azure.com/openai/v1/chat/completions"
    body = json.dumps({
        "model": "o3-mini",
        "reasoning_effort": "low",
        "messages": [
            {"role": "system", "content": _REWRITE_PROMPT},
            {"role": "user", "content": query},
        ],
    }).encode()
    req = urllib.request.Request(endpoint, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    })
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read())
            rewritten = data["choices"][0]["message"]["content"].strip()
            if rewritten:
                log.info("Query rewrite: %r -> %r", query, rewritten)
                return rewritten
    except Exception as e:
        log.warning("Query rewrite failed (fallback to original): %s", e)
    return None


def _dual_search(ov_instance, query: str, limit: int, threshold: float, rewrite_wait: float = 10):
    """Dual-path search: rewritten query + original query in parallel, merge & dedup.
    Original path is always awaited; rewritten path waits up to rewrite_wait seconds."""
    all_resources = {}

    def _search_original():
        return ov_instance.search(query, limit=limit * 2, score_threshold=threshold).resources

    def _search_rewritten():
        rewritten = rewrite_query(query)
        if rewritten and rewritten.lower().strip() != query.lower().strip():
            return ov_instance.search(rewritten, limit=limit * 2, score_threshold=threshold).resources
        return []

    with ThreadPoolExecutor(max_workers=2) as pool:
        fut_orig = pool.submit(_search_original)
        fut_rw = pool.submit(_search_rewritten)

        # Always wait for original search
        try:
            for r in fut_orig.result(timeout=5):
                all_resources[r.uri] = r
        except Exception as e:
            log.warning("original search failed: %s", e)

        # Wait for rewrite path up to rewrite_wait
        try:
            for r in fut_rw.result(timeout=rewrite_wait):
                if r.uri not in all_resources or r.score > all_resources[r.uri].score:
                    all_resources[r.uri] = r
        except Exception as e:
            log.info("rewritten search skipped: %s", type(e).__name__)

    return sorted(all_resources.values(), key=lambda r: r.score, reverse=True)


def handle(conn):
    data = conn.recv(65536).decode()
    req = json.loads(data)
    cmd = req["cmd"]
    try:
        if cmd == "search":
            query = req["query"]
            if _is_noise_query(query):
                conn.sendall(json.dumps({"ok": True, "results": []}).encode())
                return
            limit = req.get("limit", 3)
            resources = _dual_search(ov, query, limit, req.get("threshold", 0.3),
                                     rewrite_wait=req.get("rewrite_wait", 10))
            filtered = _autocut(resources)[:limit]
            out = []
            for r in filtered:
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
