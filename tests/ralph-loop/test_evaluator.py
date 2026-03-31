"""Tests for run_evaluator() in ralph_loop.py."""
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from scripts.ralph_loop import run_evaluator


@pytest.fixture
def project(tmp_path):
    """Minimal project dir with git."""
    subprocess.run(["git", "init"], cwd=str(tmp_path), capture_output=True)
    subprocess.run(["git", "commit", "--allow-empty", "-m", "init"],
                   cwd=str(tmp_path), capture_output=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
                        "PATH": "/usr/bin:/bin"})
    plan = tmp_path / "plan.md"
    plan.write_text("# Plan\n## Checklist\n- [x] done\n")
    return tmp_path, plan


def _mock_run(stdout="Verdict: PASS", returncode=0):
    """Create a mock subprocess.run result."""
    m = MagicMock()
    m.stdout = stdout
    m.stderr = ""
    m.returncode = returncode
    return m


def test_pass_on_first_cycle(project):
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        # First call = git diff, second = evaluator
        mock.side_effect = [
            _mock_run(stdout="file.py | 10 +"),  # git diff --stat
            _mock_run(stdout="Verdict: PASS"),     # evaluator
        ]
        result = run_evaluator(plan, ["echo"], tmp_path)
    assert result is True


def test_fail_after_max_cycles(project):
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        mock.return_value = _mock_run(stdout="Verdict: FAIL")
        result = run_evaluator(plan, ["echo"], tmp_path, max_cycles=2)
    assert result is False


def test_fail_triggers_fix_round(project):
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        mock.side_effect = [
            _mock_run(stdout="file.py | 10 +"),   # git diff
            _mock_run(stdout="Verdict: FAIL"),      # eval cycle 1
            _mock_run(stdout="FIXES APPLIED"),      # fix round 1
            _mock_run(stdout="Verdict: PASS"),      # eval cycle 2
        ]
        result = run_evaluator(plan, ["echo"], tmp_path, max_cycles=3)
    assert result is True
    assert mock.call_count == 4


def test_timeout_returns_none(project):
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        mock.side_effect = [
            _mock_run(stdout=""),  # git diff
            subprocess.TimeoutExpired(cmd="eval", timeout=5),
        ]
        result = run_evaluator(plan, ["echo"], tmp_path)
    assert result is None


def test_critical_finding_means_fail(project):
    """CRITICAL in output but no PASS verdict → FAIL."""
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        mock.return_value = _mock_run(stdout="CRITICAL: injection\nVerdict: FAIL")
        result = run_evaluator(plan, ["echo"], tmp_path, max_cycles=1)
    assert result is False


def test_max_three_cycles_then_fail(project):
    tmp_path, plan = project
    with patch("scripts.ralph_loop.subprocess.run") as mock:
        mock.return_value = _mock_run(stdout="Verdict: FAIL")
        result = run_evaluator(plan, ["echo"], tmp_path, max_cycles=3)
    assert result is False
    # git diff (1) + 3 eval cycles + 2 fix rounds = 6 calls
    assert mock.call_count == 6


def test_skip_eval_env(project):
    """RALPH_SKIP_EVAL is tested at the call site in main(), not in run_evaluator itself.
    This test verifies the Config parses it."""
    from scripts.ralph_loop import parse_config
    import os
    with patch.dict(os.environ, {"RALPH_SKIP_EVAL": "1"}):
        cfg = parse_config([])
    assert cfg.skip_eval == "1"
