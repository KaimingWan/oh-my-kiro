#!/usr/bin/env python3
"""OV search quality regression test — 20 cases, exit 0 if hit rate >= 83%."""
import json, socket, sys

CASES = [
    # (query, expected_substring_in_any_result_uri_or_text, description)
    ("AutoMQ 定价", "定价", "pricing doc"),
    ("Confluent 对比", "confluent", "confluent competitive"),
    ("Confluent 定价怎么样", "confluent", "confluent pricing via rewrite"),
    ("Fresha 商机", "fresha", "deal: Fresha"),
    ("Kafka 迁移", "kafka", "migration doc"),
    ("MSK 对比", "msk", "MSK competitive"),
    ("AutoMQ 架构", "automq", "architecture"),
    ("Redpanda 对比", "redpanda", "Redpanda competitive"),
    ("WarpStream 对比", "warpstream", "WarpStream competitive"),
    ("SEO 关键词", "seo", "SEO keywords"),
    ("跨 AZ 流量", "", "cross-AZ traffic (any result)"),
    ("客户案例", "", "customer cases (any result)"),
    ("弹性扩缩容", "", "auto-scaling (any result)"),
    ("存算分离", "", "storage-compute separation (any result)"),
    ("NAVER 商机", "naver", "deal: NAVER"),
    ("LG Uplus", "lg", "deal: LG Uplus"),
    ("Grab AutoMQ", "grab", "Grab case study"),
    ("EMQX AutoMQ", "emqx", "EMQX partnership"),
    ("AI 推荐话术", "ai", "AI recommendation playbook"),
    ("ok", "__EMPTY__", "noise: should return empty"),
]

THRESHOLD = 0.83
TIMEOUT = 15


def search(query: str, limit: int = 5) -> dict:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    s.connect("/tmp/omcc-ov.sock")
    s.sendall(json.dumps({"cmd": "search", "query": query, "limit": limit}).encode())
    r = json.loads(s.recv(65536).decode())
    s.close()
    return r


def main():
    hits, total = 0, len(CASES)
    failures = []
    for query, expect, desc in CASES:
        try:
            r = search(query)
            results = r.get("results", [])
            if expect == "__EMPTY__":
                ok = r.get("ok") and len(results) == 0
            elif expect == "":
                ok = r.get("ok") and len(results) > 0
            else:
                ok = r.get("ok") and any(expect.lower() in x.lower() for x in results)
            if ok:
                hits += 1
                print(f"  ✅ {desc}: {query}")
            else:
                failures.append((desc, query, results[:2]))
                print(f"  ❌ {desc}: {query} -> {results[:2]}")
        except Exception as e:
            failures.append((desc, query, [str(e)]))
            print(f"  ❌ {desc}: {query} -> ERROR: {e}")

    rate = hits / total
    print(f"\nHit rate: {hits}/{total} = {rate:.0%}")
    if failures:
        print("Failures:")
        for desc, q, r in failures:
            print(f"  - {desc}: {q}")
    sys.exit(0 if rate >= THRESHOLD else 1)


if __name__ == "__main__":
    main()
