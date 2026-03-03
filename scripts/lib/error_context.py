"""Extract error context from ralph loop log for next-iteration prompt injection."""
from __future__ import annotations
import re
from pathlib import Path

_ERROR_PATTERNS = re.compile(
    r"^(?:(?:FAIL|FAILED|Traceback|fatal:)|(?:\w+(?:Error|Exception):))",
    re.MULTILINE,
)

def extract_error_context(log_path: Path, max_lines: int = 30) -> str:
    if not log_path.exists():
        return ""
    try:
        text = log_path.read_text(errors="replace")
    except Exception:
        return ""
    if not text.strip():
        return ""
    lines = text.strip().split("\n")
    error_lines: list[str] = []
    in_block = False
    for line in reversed(lines[-200:]):
        if _ERROR_PATTERNS.search(line):
            in_block = True
        if in_block:
            error_lines.append(line)
            if len(error_lines) >= max_lines:
                break
    if not error_lines:
        return ""
    error_lines.reverse()
    return "\n".join(error_lines)[:2500]


def format_reverted_context(reverted: list[tuple[int, str]]) -> str:
    if not reverted:
        return ""
    lines = ["The following items were marked done but their verify commands FAILED (reverted to unchecked):"]
    for idx, cmd in reverted:
        lines.append(f"  #{idx}: `{cmd}` — fix the root cause, don't just re-mark it")
    return "\n".join(lines)
