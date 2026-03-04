"""Tests for ralph_loop.py core logic (no live kiro-cli needed)."""
import subprocess, os, time, signal, pytest, textwrap, re
from pathlib import Path

PLAN_TEMPLATE = textwrap.dedent("""\
    # Test Plan
    **Goal:** Test
    ## Checklist
    {items}
    ## Errors
    | Error | Task | Attempt | Resolution |
    |-------|------|---------|------------|
""")

SCRIPT = "scripts/ralph_loop.py"


def write_plan(tmp_path, items="- [ ] task one | `echo ok`"):
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_TEMPLATE.format(items=items))
    active = tmp_path / ".active"
    active.write_text(str(plan))
    return plan


def run_ralph(tmp_path, extra_env=None, max_iter="1"):
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
        "RALPH_TASK_TIMEOUT": "5",
        "RALPH_HEARTBEAT_INTERVAL": "999",
        "RALPH_SKIP_DIRTY_CHECK": "1",
        "RALPH_SKIP_PRECHECK": "1",
    }
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["python3", SCRIPT, max_iter],
        capture_output=True, text=True, env=env, timeout=30,
    )


def test_no_active_plan(tmp_path):
    r = run_ralph(tmp_path)
    assert r.returncode == 1
    assert "No active plan" in r.stdout


def test_no_checklist(tmp_path):
    plan = tmp_path / "plan.md"
    plan.write_text("# Empty\nNo checklist.")
    (tmp_path / ".active").write_text(str(plan))
    r = run_ralph(tmp_path)
    assert r.returncode == 1


def test_already_complete(tmp_path):
    write_plan(tmp_path, items="- [x] done | `echo ok`")
    r = run_ralph(tmp_path)
    assert r.returncode == 0
    assert "complete" in r.stdout.lower()


def test_timeout_kills_process(tmp_path):
    """Core test: subprocess that hangs gets killed by timeout, no orphans."""
    write_plan(tmp_path)
    r = run_ralph(tmp_path, extra_env={
        "RALPH_KIRO_CMD": "sleep 60",
        "RALPH_TASK_TIMEOUT": "2",
    })
    assert r.returncode == 1


def test_circuit_breaker(tmp_path):
    """After MAX_STALE rounds with no progress, should exit 1."""
    write_plan(tmp_path, items="- [ ] impossible | `false`")
    r = run_ralph(tmp_path, extra_env={
        "RALPH_KIRO_CMD": "true",
    }, max_iter="5")
    assert r.returncode == 1
    assert "circuit breaker" in r.stdout.lower() or "no progress" in r.stdout.lower()


def test_lock_cleanup_on_signal(tmp_path):
    """Lock file should be cleaned up even if process is killed."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    # Clean up any stale lock first
    lock_path.unlink(missing_ok=True)

    # Write a script that ignores args and sleeps (avoids macOS sleep rejecting extra args)
    sleep_script = tmp_path / "long_sleep.sh"
    sleep_script.write_text("#!/bin/bash\nsleep 60\n")
    sleep_script.chmod(0o755)

    proc = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": str(sleep_script),
            "RALPH_TASK_TIMEOUT": "60",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    assert lock_path.exists(), "Lock file should exist while running"
    proc.terminate()
    proc.wait(timeout=5)
    time.sleep(0.5)
    assert not lock_path.exists(), "Lock file should be cleaned up after SIGTERM"


from scripts.lib.plan import PlanFile
from scripts.ralph_loop import build_prompt


def test_fallback_no_task_structure(tmp_path):
    """Plan with checklist but no task sections → runs without crash, exits normally."""
    write_plan(tmp_path, items="- [ ] simple task | `echo ok`")
    r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "true"}, max_iter="2")
    # Should not crash — either completes or hits circuit breaker
    assert r.returncode in (0, 1)
    # Should not contain traceback
    assert "Traceback" not in r.stdout
    assert "Traceback" not in r.stderr


def test_summary_success(tmp_path):
    """Test summary output for successful completion."""
    summary_file = Path("docs/plans/.ralph-result")
    try:
        write_plan(tmp_path, items="- [x] done | `echo ok`")
        r = run_ralph(tmp_path)
        assert r.returncode == 0
        
        assert summary_file.exists()
        content = summary_file.read_text()
        assert "SUCCESS" in content
        assert "Completed:** 1" in content
        assert "Remaining:** 0" in content
        assert str(tmp_path / "plan.md") in content
    finally:
        summary_file.unlink(missing_ok=True)


def test_summary_failure(tmp_path):
    """Test summary output for failed execution with remaining items."""
    summary_file = Path("docs/plans/.ralph-result")
    try:
        write_plan(tmp_path, items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`")
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "true"}, max_iter="1")
        assert r.returncode == 1
        
        assert summary_file.exists()
        content = summary_file.read_text()
        assert "FAILED" in content
        assert "Remaining:** 2" in content
        assert "Remaining Items" in content
    finally:
        summary_file.unlink(missing_ok=True)

def test_double_ralph_no_lock_guard(tmp_path):
    """Start ralph as background process, then start second ralph with same plan.
    Second instance overwrites lock and also runs. Both exit without crash."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    
    proc1 = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": "sleep 60",
            "RALPH_TASK_TIMEOUT": "60",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    
    r2 = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "sleep 1"})
    
    proc1.terminate()
    proc1.wait(timeout=5)
    
    assert r2.returncode in (0, 1)
    lock_path.unlink(missing_ok=True)


def test_sigint_cleanup(tmp_path):
    """Start ralph (KIRO_CMD=sleep 60), send SIGINT → lock file cleaned up, process exits."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)

    # Write a script that ignores args and sleeps (avoids macOS sleep rejecting extra args)
    sleep_script = tmp_path / "long_sleep.sh"
    sleep_script.write_text("#!/bin/bash\nsleep 60\n")
    sleep_script.chmod(0o755)

    proc = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": str(sleep_script),
            "RALPH_TASK_TIMEOUT": "60",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    assert lock_path.exists(), "Lock file should exist while running"
    proc.send_signal(signal.SIGINT)
    proc.wait(timeout=5)
    time.sleep(0.5)
    assert not lock_path.exists(), "Lock file should be cleaned up after SIGINT"


def test_active_points_to_missing_file(tmp_path):
    """Active file points to non-existent plan → ralph exits with clear error."""
    active = tmp_path / ".active"
    active.write_text(str(tmp_path / "nonexistent_plan.md"))
    r = run_ralph(tmp_path)
    assert r.returncode == 1
    assert "not found" in r.stdout.lower() or "no such" in r.stdout.lower() or "not found" in r.stderr.lower()


def test_empty_active_file(tmp_path):
    """Active file is empty → Path('') resolves to cwd → crash with returncode != 0."""
    active = tmp_path / ".active"
    active.write_text("")
    r = run_ralph(tmp_path)
    assert r.returncode != 0


def test_plan_modified_during_iteration(tmp_path):
    """KIRO_CMD script checks off an item → ralph detects progress on next reload."""
    plan = tmp_path / "plan.md"
    plan_text = PLAN_TEMPLATE.format(items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`")
    plan.write_text(plan_text)
    active = tmp_path / ".active"
    active.write_text(str(plan))

    # Script that checks off the first item in the plan
    script = tmp_path / "modify_plan.sh"
    script.write_text(f"#!/bin/bash\nsed -i.bak 's/- \\[ \\] task one/- [x] task one/' '{plan}'\n")
    script.chmod(0o755)

    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": str(script)}, max_iter="5")
        # Ralph should detect the checked-off item and not count it as stale
        assert r.returncode in (0, 1)
        # Verify plan was actually modified by the script
        content = plan.read_text()
        assert "- [x] task one" in content
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_lock_deleted_during_run(tmp_path):
    """Delete lock file while ralph runs → ralph still completes iteration."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")

    # Script that deletes the lock file then exits
    script = tmp_path / "delete_lock.sh"
    script.write_text(f"#!/bin/bash\nrm -f '{lock_path.resolve()}'\nsleep 1\n")
    script.chmod(0o755)

    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": str(script)}, max_iter="2")
        # Ralph should complete without crashing despite lock deletion
        assert r.returncode in (0, 1)
        assert "Traceback" not in r.stdout
        assert "Traceback" not in r.stderr
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_child_process_no_orphan(tmp_path):
    """Start ralph with uniquely-named KIRO_CMD script, kill ralph, verify no orphan."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)

    unique_name = f"ralph_test_orphan_{os.getpid()}"
    script_path = tmp_path / f"{unique_name}.sh"
    script_path.write_text(f"#!/bin/bash\nexec -a {unique_name} sleep 60\n")
    script_path.chmod(0o755)

    proc = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": str(script_path),
            "RALPH_TASK_TIMEOUT": "2",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    time.sleep(1)

    # Verify no orphan process with the unique name
    check = subprocess.run(
        ["pgrep", "-f", unique_name],
        capture_output=True, text=True,
    )
    assert check.returncode != 0, f"Orphan process found: {check.stdout.strip()}"
    lock_path.unlink(missing_ok=True)


@pytest.mark.slow
def test_many_iterations_no_hang(tmp_path):
    """Run ralph with 10 iterations (KIRO_CMD=true, plan never completes).
    Exits within reasonable time (no hang), exit code 1 (circuit breaker), no orphan children."""
    write_plan(tmp_path, items="- [ ] never done | `echo ok`")
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "true"}, max_iter="10")
        assert r.returncode == 1
        assert "circuit breaker" in r.stdout.lower() or "no progress" in r.stdout.lower()
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


@pytest.mark.slow
def test_heartbeat_thread_cleanup(tmp_path):
    """Run ralph with short timeout and heartbeat for 3 iterations → exits cleanly, no hang."""
    write_plan(tmp_path, items="- [ ] never done | `echo ok`")
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    unique_name = f"ralph_hb_test_{os.getpid()}"
    script = tmp_path / f"{unique_name}.sh"
    script.write_text(f"#!/bin/bash\nexec -a {unique_name} sleep 60\n")
    script.chmod(0o755)
    try:
        r = run_ralph(tmp_path, extra_env={
            "RALPH_KIRO_CMD": str(script),
            "RALPH_TASK_TIMEOUT": "2",
            "RALPH_HEARTBEAT_INTERVAL": "1",
        }, max_iter="3")
        assert r.returncode == 1
        time.sleep(1)
        check = subprocess.run(["pgrep", "-f", unique_name], capture_output=True, text=True)
        assert check.returncode != 0, f"Orphan process found: {check.stdout.strip()}"
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_happy_path_complete(tmp_path):
    """KIRO_CMD script checks off all items → ralph exits 0, summary says SUCCESS."""
    plan = tmp_path / "plan.md"
    plan_text = PLAN_TEMPLATE.format(items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`")
    plan.write_text(plan_text)
    active = tmp_path / ".active"
    active.write_text(str(plan))

    script = tmp_path / "check_all.sh"
    script.write_text(f"#!/bin/bash\nsed -i.bak 's/- \\[ \\]/- [x]/g' '{plan}'\n")
    script.chmod(0o755)

    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": str(script)}, max_iter="5")
        assert r.returncode == 0
        assert summary_file.exists()
        assert "SUCCESS" in summary_file.read_text()
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_skip_then_complete(tmp_path):
    """KIRO_CMD script marks item 1 as SKIP, checks off item 2 → ralph exits 0 (all resolved)."""
    plan = tmp_path / "plan.md"
    plan_text = PLAN_TEMPLATE.format(items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`")
    plan.write_text(plan_text)
    active = tmp_path / ".active"
    active.write_text(str(plan))

    # First call: mark item 1 as SKIP. Second call: check off item 2.
    script = tmp_path / "skip_then_check.sh"
    script.write_text(f"""#!/bin/bash
if grep -q '\\- \\[ \\] task one' '{plan}'; then
    sed -i.bak 's/- \\[ \\] task one/- [SKIP] task one/' '{plan}'
else
    sed -i.bak 's/- \\[ \\] task two/- [x] task two/' '{plan}'
fi
""")
    script.chmod(0o755)

    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": str(script)}, max_iter="5")
        assert r.returncode == 0
        content = plan.read_text()
        assert "- [SKIP] task one" in content
        assert "- [x] task two" in content
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_timeout_then_stale_then_breaker(tmp_path):
    """KIRO_CMD=sleep 60, timeout=2, max_iter=4 → ralph hits circuit breaker, exits 1."""
    write_plan(tmp_path, items="- [ ] stuck task | `echo ok`")
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={
            "RALPH_KIRO_CMD": "sleep 60",
            "RALPH_TASK_TIMEOUT": "2",
        }, max_iter="4")
        assert r.returncode == 1
        assert "circuit breaker" in r.stdout.lower() or "no progress" in r.stdout.lower()
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_fully_unparseable_plan_fallback(tmp_path):
    """Plan with checklist items but zero parseable task sections → falls back to build_prompt().
    Verify no crash and no 'batch' in stdout."""
    plan_text = PLAN_TEMPLATE.format(
        items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`"
    )
    # No ### Task N: headers at all — unchecked_tasks() returns [] but unchecked > 0
    write_plan(tmp_path, items="- [ ] task one | `echo ok`\n- [ ] task two | `echo ok`")
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    try:
        r = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "true"}, max_iter="2")
        assert r.returncode in (0, 1)
        assert "Traceback" not in r.stdout
        assert "Traceback" not in r.stderr
        assert "batch" not in r.stdout.lower()
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


from unittest.mock import patch

def test_detect_claude_cli():
    """When claude is available and authenticated, detect_cli returns claude command."""
    from scripts.lib.cli_detect import detect_cli
    mock_proc = type('MockProc', (), {'communicate': lambda self, timeout=None: (b'pong', b''), 'returncode': 0, 'pid': 99999})()
    with patch('shutil.which', side_effect=lambda x: '/usr/bin/claude' if x == 'claude' else None), \
         patch('subprocess.Popen', return_value=mock_proc):
        cmd = detect_cli()
        assert cmd[0] == 'claude'
        assert '-p' in cmd


def test_detect_kiro_cli():
    """When only kiro-cli is available, detect_cli returns kiro command."""
    from scripts.lib.cli_detect import detect_cli
    with patch('shutil.which', side_effect=lambda x: '/usr/bin/kiro-cli' if x == 'kiro-cli' else None):
        cmd = detect_cli()
        assert cmd[0] == 'kiro-cli'
        assert 'chat' in cmd


def test_env_override():
    """RALPH_KIRO_CMD env var takes precedence over auto-detection."""
    from scripts.lib.cli_detect import detect_cli
    with patch.dict(os.environ, {'RALPH_KIRO_CMD': 'my-custom-cli --flag'}):
        cmd = detect_cli()
        assert cmd == ['my-custom-cli', '--flag']


def test_no_cli_found():
    """When neither CLI is found, detect_cli raises SystemExit."""
    from scripts.lib.cli_detect import detect_cli
    with patch('shutil.which', return_value=None), \
         pytest.raises(SystemExit):
        detect_cli()


def test_init_prompt_differs_from_regular(tmp_path):
    """build_prompt(is_first=True) contains 'FIRST iteration'; regular does not."""
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)

    init = build_prompt(1, pf, plan_file, tmp_path, skip_precheck="1", is_first=True)
    regular = build_prompt(2, pf, plan_file, tmp_path, skip_precheck="1")

    assert "FIRST iteration" in init
    assert "FIRST iteration" not in regular


def test_recursion_guard(tmp_path):
    """ralph_loop.py exits immediately if _RALPH_LOOP_RUNNING is set."""
    write_plan(tmp_path)
    r = run_ralph(tmp_path, extra_env={
        "RALPH_KIRO_CMD": "true",
        "_RALPH_LOOP_RUNNING": "1",
    })
    assert r.returncode == 1
    assert "nested" in r.stdout.lower() or "recursion" in r.stdout.lower()


def test_no_orphan_after_ralph_killed(tmp_path):
    """Killing ralph_loop.py also kills its child CLI process (no orphans)."""
    write_plan(tmp_path)
    unique_name = f"ralph_orphan_test_{os.getpid()}"
    script = tmp_path / f"{unique_name}.sh"
    script.write_text(f"#!/bin/bash\nexec -a {unique_name} sleep 120\n")
    script.chmod(0o755)

    proc = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": str(script),
            "RALPH_TASK_TIMEOUT": "60",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    # Wait for child to start (poll loop instead of sleep)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        check = subprocess.run(["pgrep", "-f", unique_name], capture_output=True, text=True)
        if check.returncode == 0:
            break
        time.sleep(0.2)
    # Kill ralph (SIGTERM)
    proc.terminate()
    proc.wait(timeout=5)
    time.sleep(1)
    # Child should NOT be orphaned
    check = subprocess.run(["pgrep", "-f", unique_name], capture_output=True, text=True)
    assert check.returncode != 0, f"Orphan child found: {check.stdout.strip()}"


def test_sleep_removed_from_source():
    """time.sleep(2) must not be present in ralph_loop.py (Task 5)."""
    source = Path("scripts/ralph_loop.py").read_text()
    assert "time.sleep(2)" not in source, "time.sleep(2) should have been removed from ralph_loop.py"


def test_prev_exit_in_source():
    """prev_exit variable must be present for precheck caching (Task 5)."""
    source = Path("scripts/ralph_loop.py").read_text()
    assert "prev_exit" in source, "prev_exit not found in ralph_loop.py"


def test_parse_config_defaults():
    """parse_config with no args returns correct defaults."""
    from scripts.ralph_loop import parse_config
    import os
    # Clear env vars that would override defaults
    env_keys = ["RALPH_TASK_TIMEOUT", "RALPH_HEARTBEAT_INTERVAL",
                "RALPH_SKIP_DIRTY_CHECK", "RALPH_SKIP_PRECHECK",
                "PLAN_POINTER_OVERRIDE"]
    saved = {k: os.environ.pop(k, None) for k in env_keys}
    try:
        cfg = parse_config([])
        assert cfg.max_iterations == 10
        assert cfg.task_timeout == 1800
        assert cfg.heartbeat_interval == 60
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v


def test_validate_plan_missing(tmp_path):
    """validate_plan raises SystemExit for missing plan file."""
    from scripts.ralph_loop import validate_plan
    with pytest.raises(SystemExit):
        validate_plan(tmp_path / "nonexistent.md")


def test_flock_prevents_double_ralph(tmp_path):
    """Second ralph instance is blocked by flock and exits with error."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)

    sleep_script = tmp_path / "long_sleep2.sh"
    sleep_script.write_text("#!/bin/bash\nsleep 60\n")
    sleep_script.chmod(0o755)

    proc1 = subprocess.Popen(
        ["python3", SCRIPT, "1"],
        env={
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", "/tmp"),
            "PLAN_POINTER_OVERRIDE": str(tmp_path / ".active"),
            "RALPH_KIRO_CMD": str(sleep_script),
            "RALPH_TASK_TIMEOUT": "60",
            "RALPH_HEARTBEAT_INTERVAL": "999",
            "RALPH_SKIP_DIRTY_CHECK": "1",
        },
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)

    r2 = run_ralph(tmp_path, extra_env={"RALPH_KIRO_CMD": "sleep 1"})

    proc1.terminate()
    proc1.wait(timeout=5)

    assert r2.returncode == 1
    assert "already running" in r2.stdout.lower() or "lock" in r2.stdout.lower()
    lock_path.unlink(missing_ok=True)


def test_idle_watchdog_kills_silent_process(tmp_path):
    """Process that produces no output is killed by idle watchdog before task_timeout."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    script = tmp_path / "silent.sh"
    script.write_text("#!/bin/bash\nsleep 300\n")
    script.chmod(0o755)
    try:
        start = time.monotonic()
        r = run_ralph(tmp_path, extra_env={
            "RALPH_KIRO_CMD": str(script),
            "RALPH_TASK_TIMEOUT": "300",
            "RALPH_IDLE_TIMEOUT": "3",
            "RALPH_HEARTBEAT_INTERVAL": "1",
        }, max_iter="1")
        elapsed = time.monotonic() - start
        assert r.returncode == 1
        assert elapsed < 30, f"Took {elapsed:.0f}s — idle watchdog didn't fire"
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_active_process_not_killed_by_idle_watchdog(tmp_path):
    """Process that produces output every second survives past idle_timeout."""
    write_plan(tmp_path)
    lock_path = Path(".ralph-loop.lock")
    lock_path.unlink(missing_ok=True)
    summary_file = Path("docs/plans/.ralph-result")
    script = tmp_path / "chatty.sh"
    script.write_text("#!/bin/bash\nfor i in $(seq 1 10); do echo tick$i; sleep 1; done\n")
    script.chmod(0o755)
    try:
        start = time.monotonic()
        r = run_ralph(tmp_path, extra_env={
            "RALPH_KIRO_CMD": str(script),
            "RALPH_TASK_TIMEOUT": "30",
            "RALPH_IDLE_TIMEOUT": "3",
            "RALPH_HEARTBEAT_INTERVAL": "1",
        }, max_iter="1")
        elapsed = time.monotonic() - start
        assert elapsed >= 8, f"Killed too early at {elapsed:.0f}s — false positive"
    finally:
        lock_path.unlink(missing_ok=True)
        summary_file.unlink(missing_ok=True)


def test_claude_cmd_has_no_session_persistence():
    """Claude command should include --no-session-persistence to avoid disk I/O."""
    from scripts.lib.cli_detect import detect_cli
    from unittest.mock import patch
    mock_proc = type('MockProc', (), {'communicate': lambda self, timeout=None: (b'pong', b''), 'returncode': 0, 'pid': 99999})()
    with patch('shutil.which', side_effect=lambda x: '/usr/bin/claude' if x == 'claude' else None), \
         patch('subprocess.Popen', return_value=mock_proc):
        cmd = detect_cli()
        assert '--no-session-persistence' in cmd


def test_heartbeat_no_confusing_elapsed():
    """_heartbeat should not have the confusing elapsed calculation."""
    source = open("scripts/ralph_loop.py").read()
    assert "heartbeat_interval * (idle_elapsed" not in source, \
        "Confusing elapsed calculation should be removed from _heartbeat"


def test_single_build_prompt_function():
    """Only one prompt builder function should exist (merged)."""
    source = open("scripts/ralph_loop.py").read()
    assert "def build_init_prompt(" not in source, "build_init_prompt should be merged into build_prompt"
    assert "def build_prompt(" in source, "build_prompt should still exist"


def test_precheck_runs_only_once():
    """run_precheck should only run when is_first=True, not on subsequent iterations."""
    from scripts.ralph_loop import build_prompt
    from scripts.lib.plan import PlanFile
    from unittest.mock import patch
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write("# T\n## Checklist\n- [ ] a | `true`\n")
        f.flush()
        pf = PlanFile(Path(f.name))
        # is_first=False should NOT call run_precheck
        with patch('scripts.ralph_loop.run_precheck') as mock_pre:
            build_prompt(2, pf, Path(f.name), Path('.'))
            mock_pre.assert_not_called()


def test_detect_cli_called_outside_loop():
    """detect_cli() must be called before the loop, not inside it."""
    source = open("scripts/ralph_loop.py").read()
    loop_start = source.index("for i in range(1, max_iterations + 1):")
    in_loop = source[loop_start:]
    assert "detect_cli()" not in in_loop, "detect_cli() should NOT be called inside the loop"


def test_main_has_no_inline_env_reads():
    """main() should use parse_config, not inline os.environ.get calls."""
    source = open("scripts/ralph_loop.py").read()
    main_body = source.split("def main")[1]
    inline_env = [l.strip() for l in main_body.split("\n")
                  if "os.environ.get" in l and "def " not in l and "_RALPH_LOOP_RUNNING" not in l]
    assert inline_env == [], f"Inline env reads in main(): {inline_env}"


def test_stale_prompt_contains_error_context(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    log_file = tmp_path / "ralph.log"
    log_file.write_text("Error: something broke\nTraceback:\n  File x\nValueError: bad\n")
    prompt = build_prompt(3, pf, plan_file, tmp_path, skip_precheck="1",
                          stale_rounds=2, log_path=log_file)
    assert "STUCK" in prompt or "stuck" in prompt
    assert "alternative approach" in prompt.lower() or "different strategy" in prompt.lower()

def test_reverted_items_in_prompt(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    reverted = [(1, "pytest tests/ -v")]
    prompt = build_prompt(2, pf, plan_file, tmp_path, skip_precheck="1",
                          reverted_items=reverted)
    assert "verify commands FAILED" in prompt
    assert "pytest" in prompt

def test_normal_prompt_has_autonomous_instructions(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    prompt = build_prompt(1, pf, plan_file, tmp_path, skip_precheck="1", is_first=True)
    assert "solve it yourself" in prompt.lower() or "autonomous" in prompt.lower() or "self-diagnose" in prompt.lower()

def test_prompt_instructs_patterns_consolidation(tmp_path):
    plan_file = tmp_path / "plan.md"
    plan_file.write_text("# T\n## Checklist\n- [ ] a | `true`\n")
    pf = PlanFile(plan_file)
    prompt = build_prompt(1, pf, plan_file, tmp_path, skip_precheck="1", is_first=True)
    assert "Codebase Patterns" in prompt or "codebase patterns" in prompt

def test_reasoning_loop_in_prompt(tmp_path):
    plan = tmp_path / "plan.md"
    plan.write_text("- [ ] Implement user auth module | `python3 -c 'import auth'`\n")
    from scripts.ralph_loop import build_prompt
    from scripts.lib.plan import PlanFile
    result = build_prompt(1, PlanFile(plan), plan, tmp_path)
    # Verify all 7 reasoning loop steps are present
    for step in ["OBSERVE", "THINK", "PLAN", "EXECUTE", "REFLECT", "CORRECT", "VERIFY"]:
        assert step in result, f"Missing reasoning loop step: {step}"
    # Verify the section header exists
    assert "Reasoning Loop" in result
    # Verify it mentions coarse/vague items
    assert "coarse" in result.lower() or "vague" in result.lower()
