#!/usr/bin/env python3
"""consolidate-episodes.py — Merge duplicate episodes by keyword overlap, add [hits:N] tags.

Usage:
  python3 consolidate-episodes.py --dry-run < episodes.md   # preview to stdout
  python3 consolidate-episodes.py < episodes.md             # output consolidated to stdout
"""
import sys
import re
from collections import defaultdict

KEYWORD_OVERLAP_THRESHOLD = 0.6  # 60% keyword overlap → merge


def parse_episodes(lines):
    """Parse episode lines into structured entries. Preserve non-episode lines."""
    entries = []
    other_lines = []
    for line in lines:
        line = line.rstrip('\n')
        # Match: DATE | STATUS | KEYWORDS | SUMMARY
        m = re.match(r'^(\d{4}-\d{2}-\d{2})\s*\|\s*(\w+)\s*\|\s*([^|]+)\|\s*(.+)$', line)
        if m:
            date, status, kw_str, summary = m.group(1), m.group(2), m.group(3), m.group(4)
            keywords = set(k.strip() for k in kw_str.split(',') if k.strip())
            # Extract existing hits tag
            hits_m = re.search(r'\[hits:(\d+)\]', summary)
            hits = int(hits_m.group(1)) if hits_m else 1
            summary_clean = re.sub(r'\s*\[hits:\d+\]\s*$', '', summary).strip()
            entries.append({
                'date': date, 'status': status, 'keywords': keywords,
                'summary': summary_clean, 'hits': hits, 'original': line,
            })
        else:
            other_lines.append(line)
    return entries, other_lines


def keyword_overlap(a, b):
    if not a or not b:
        return 0.0
    intersection = a & b
    return len(intersection) / min(len(a), len(b))


def consolidate(entries):
    """Merge entries with ≥60% keyword overlap. Keep newest date, sum hits."""
    merged = []
    used = set()
    for i, e in enumerate(entries):
        if i in used:
            continue
        group = [e]
        for j in range(i + 1, len(entries)):
            if j in used:
                continue
            if e['status'] == entries[j]['status'] and keyword_overlap(e['keywords'], entries[j]['keywords']) >= KEYWORD_OVERLAP_THRESHOLD:
                group.append(entries[j])
                used.add(j)
        # Merge group: newest date, union keywords, highest hits sum, longest summary
        newest = max(group, key=lambda x: x['date'])
        all_kw = set()
        total_hits = 0
        for g in group:
            all_kw |= g['keywords']
            total_hits += g['hits']
        best_summary = max(group, key=lambda x: len(x['summary']))['summary']
        merged.append({
            'date': newest['date'], 'status': newest['status'],
            'keywords': all_kw, 'summary': best_summary, 'hits': total_hits,
        })
    return merged


def format_entry(e):
    kw_str = ','.join(sorted(e['keywords']))
    hits_tag = f" [hits:{e['hits']}]" if e['hits'] > 1 else ""
    return f"{e['date']} | {e['status']} | {kw_str} | {e['summary']}{hits_tag}"


def main():
    dry_run = '--dry-run' in sys.argv
    lines = sys.stdin.readlines()
    entries, other_lines = parse_episodes(lines)
    if not entries:
        # No episodes found, pass through
        for line in lines:
            sys.stdout.write(line if line.endswith('\n') else line + '\n')
        return
    merged = consolidate(entries)
    # Output: other lines (header/comments) first, then merged entries
    for line in other_lines:
        print(line)
    for e in merged:
        print(format_entry(e))


if __name__ == '__main__':
    main()
