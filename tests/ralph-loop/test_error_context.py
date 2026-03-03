import pytest
from pathlib import Path
from scripts.lib.error_context import extract_error_context

def test_extracts_last_error_from_log(tmp_path):
    log = tmp_path / "test.log"
    log.write_text(
        "normal output\n"
        "Error: module 'foo' has no attribute 'bar'\n"
        "Traceback (most recent call last):\n"
        "  File \"test.py\", line 10\n"
        "AttributeError: module 'foo' has no attribute 'bar'\n"
        "more output\n"
    )
    ctx = extract_error_context(log, max_lines=50)
    assert "AttributeError" in ctx
    assert len(ctx) < 3000

def test_empty_log(tmp_path):
    log = tmp_path / "test.log"
    log.write_text("")
    assert extract_error_context(log) == ""

def test_no_errors(tmp_path):
    log = tmp_path / "test.log"
    log.write_text("all good\nno problems here\n")
    assert extract_error_context(log) == ""

def test_missing_log(tmp_path):
    assert extract_error_context(tmp_path / "nope.log") == ""

def test_reverted_items_context():
    reverted = [(1, "pytest tests/ -v"), (3, "bash -n hook.sh")]
    from scripts.lib.error_context import format_reverted_context
    ctx = format_reverted_context(reverted)
    assert "#1" in ctx
    assert "pytest" in ctx
