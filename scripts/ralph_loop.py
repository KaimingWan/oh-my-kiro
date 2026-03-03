#!/usr/bin/env python3
from __future__ import annotations
"""ralph_loop.py — Kiro CLI wrapper with Ralph Loop discipline.

Keeps restarting Kiro until all checklist items in the active plan are checked off.
Usage: python3 scripts/ralph_loop.py [max_iterations]
"""
import atexit
import os
import re
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Callable

# --- Resolve project root & imports ---
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from scripts.lib.plan import PlanFile
from scripts.lib.error_context import extract_error_context, format_reverted_context
from scripts.lib.lock import LockFile
from scripts.lib.cli_detect import detect_cli
from scripts.lib.precheck import run_precheck
from scripts.lib.pty_runner import pty_run


def die(msg: str) -> None:
    print(f"❌ {msg}")
    sys.exit(1)


# --- Signal handling + cleanup ---
def make_cleanup_handler(child_proc_ref: list, lock: LockFile,
                         shutdown_flag: list | None = None):
    """Factory returning a cleanup handler that closes over mutable state.

    If shutdown_flag (single-element list) is provided, handler sets flag[0]=True
    instead of calling sys.exit, making it async-signal-safe.
    """
    def _cleanup_handler(signum=None, frame=None):
        cp = child_proc_ref[0]
        if cp is not None:
            try:
                os.killpg(os.getpgid(cp.pid), signal.SIGTERM)
            except (ProcessLookupError, OSError):
                pass
        if shutdown_flag is not None:
            shutdown_flag[0] = True
        else:
            lock.release()
            sys.exit(1)
    return _cleanup_handler


# --- Heartbeat thread ---
def _heartbeat(proc: subprocess.Popen, iteration: int, stop_event: threading.Event,
               plan: PlanFile, heartbeat_interval: int,
               log_path: Path | None = None, idle_timeout: int = 0):
    last_size = log_path.stat().st_size if (log_path and log_path.exists()) else 0
    idle_elapsed = 0
    while not stop_event.wait(heartbeat_interval):
        if proc.poll() is not None:
            break
        plan.reload()
        if log_path:
            cur_size = log_path.stat().st_size if log_path.exists() else 0
            if cur_size > last_size:
                last_size = cur_size
                idle_elapsed = 0
            else:
                idle_elapsed += heartbeat_interval
            if idle_timeout > 0 and idle_elapsed >= idle_timeout:
                ts = datetime.now().strftime("%H:%M:%S")
                print(f"🧊 [{ts}] No output for {idle_elapsed}s — restarting",
                      flush=True)
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                except (ProcessLookupError, OSError):
                    pass
                break
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"💓 [{ts}] {plan.checked}/{plan.total} done",
              flush=True)


# --- Summary writer ---
def write_summary(exit_code: int, plan: PlanFile, plan_path: Path, summary_file: Path):
    plan.reload()
    status = "✅ SUCCESS" if exit_code == 0 else "❌ FAILED"
    lines = [
        "# Ralph Loop Result", "",
        f"- **Status:** {status} (exit {exit_code})",
        f"- **Plan:** {plan_path}",
        f"- **Completed:** {plan.checked}",
        f"- **Remaining:** {plan.unchecked}",
        f"- **Skipped:** {plan.skipped}",
        f"- **Finished at:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
    ]
    if plan.unchecked > 0:
        lines += ["", "## Remaining Items"] + plan.next_unchecked(50)
    summary = "\n".join(lines)
    summary_file.parent.mkdir(parents=True, exist_ok=True)
    summary_file.write_text(summary)
    print(f"\n{summary}", flush=True)


# --- Build prompt ---
def build_prompt(iteration: int, plan: PlanFile, plan_path: Path, project_root: Path,
                 skip_precheck: str = "", prev_exit: int = -1, is_first: bool = False,
                 work_dir: str = "", stale_rounds: int = 0, log_path: Path | None = None,
                 reverted_items: list[tuple[int, str]] | None = None) -> str:
    plan.reload()
    progress_file = plan.progress_path
    findings_file = plan.findings_path
    next_items = "\n".join(plan.next_unchecked(5))

    if is_first:
        if skip_precheck:
            env_status = "⏭️ Precheck skipped"
        else:
            precheck_ok, precheck_out = run_precheck(project_root)
            env_status = "✅ Environment OK" if precheck_ok else f"❌ Environment FAILING:\n{precheck_out}"
        header = "You are executing a plan (FIRST iteration — environment setup and verification)."
        pre_items = """This is the FIRST iteration. Before implementing anything:
1. Verify the environment is set up correctly (dependencies installed, tests runnable).
2. If environment is failing, fix it first before proceeding.
3. Then implement the FIRST unchecked item below."""
    else:
        env_status = "✅ Environment OK (cached)"
        header = "You are executing a plan."
        pre_items = ""

    work_dir_section = ""
    if work_dir:
        work_dir_section = f"""
Working directory: {work_dir}
You MUST work in this directory. All file edits, test runs, and git commits happen here.
The plan file is in the parent project — read it but do NOT modify files outside your working directory.
"""

    # Stale/error context injection
    stale_section = ""
    if stale_rounds >= 2 and log_path:
        error_ctx = extract_error_context(log_path)
        stale_section = f"""
⚠️ STUCK: {stale_rounds} rounds with no progress. Previous errors:
{error_ctx if error_ctx else '(no error output captured)'}

You MUST try a DIFFERENT STRATEGY. The previous approach failed — do not repeat it.
Consider: alternative implementation, different library, simpler approach, or breaking the task down.
"""
    elif stale_rounds >= 2:
        stale_section = f"""
⚠️ STUCK: {stale_rounds} rounds with no progress.
You MUST try a DIFFERENT STRATEGY. The previous approach failed — do not repeat it.
"""

    reverted_section = ""
    if reverted_items:
        reverted_section = format_reverted_context(reverted_items)

    return f"""{header}

Read these files first:
1. Plan: {plan_path}
2. Progress log: {progress_file} (if exists — contains learnings from previous iterations)
3. Findings: {findings_file} (if exists — contains research discoveries and decisions)

Environment: {env_status}
{stale_section}{reverted_section}
{work_dir_section}
{pre_items + chr(10) if pre_items else ""}Next unchecked items:
{next_items}

Rules:
1. Implement the FIRST unchecked item. Verify it works (run tests/typecheck).
2. If the checklist item has an inline verify command (format: `| `cmd``), run it. Only mark `- [x]` if the verify command exits 0. If no verify command, manually confirm the task is done before marking.
3. IMPORTANT: The unchecked item may reference work defined in an earlier Phase. Read the FULL Phase section containing that item (including code blocks) before implementing. Do NOT just check the box — execute the implementation code first.
4. Update the plan: change that item from '- [ ]' to '- [x]'.
5. Append to {progress_file} with format:
   ## Iteration {iteration} — $(date)
   - **Task:** <what you did>
   - **Files changed:** <list>
   - **Learnings:** <gotchas, patterns discovered>
   - **Status:** done / skipped
6. If you discover reusable patterns or make technical decisions, write to {findings_file}.
7. Commit: feat: <item description>.
8. You are AUTONOMOUS — self-diagnose errors, research solutions, try alternative approaches. Do NOT stop or ask for help. Solve it yourself.
9. If stuck after 3 attempts, try a DIFFERENT STRATEGY before giving up. Change item to '- [SKIP] <reason>' only as last resort.
10. If a command is blocked by a security hook, read the suggested alternative and retry with the safe command. If blocked 3+ times on the same item, mark it as '- [SKIP] blocked by security hook' and continue.
11. NEVER mark an item `- [x]` if the verify command fails or the implementation was not actually executed. If unsure, re-run the verify command.
12. Codebase Patterns: When you discover patterns (naming conventions, error handling idioms, test structure), note them in {findings_file} under a "## Codebase Patterns" section so future iterations can reuse them.
"""





from dataclasses import dataclass

@dataclass
class Config:
    max_iterations: int = 10
    task_timeout: int = 1800
    idle_timeout: int = 60
    heartbeat_interval: int = 30
    skip_dirty_check: str = ""
    skip_precheck: str = ""
    plan_pointer: Path | None = None
    instance_slug: str = ""
    work_dir: str = ""

    def __post_init__(self):
        if self.plan_pointer is None:
            self.plan_pointer = Path("docs/plans/.active")

    def instance_path(self, base: str) -> Path:
        """Return instance-isolated path. E.g. '.ralph-loop.lock' → '.ralph-loop-{slug}.lock'."""
        if not self.instance_slug:
            return Path(base)
        p = Path(base)
        stem, suffix = p.stem, p.suffix
        return p.with_name(f"{stem}-{self.instance_slug}{suffix}")


def parse_config(argv: list[str] | None = None) -> Config:
    """Parse configuration from argv and environment variables."""
    argv = argv or []
    max_iter = int(argv[0]) if argv else 10
    plan_pointer = Path(os.environ.get("PLAN_POINTER_OVERRIDE", "docs/plans/.active"))
    # Derive instance slug: non-default pointer → filename stem; default (.active) → empty
    slug = "" if plan_pointer.name == ".active" else plan_pointer.stem
    return Config(
        max_iterations=max_iter,
        task_timeout=int(os.environ.get("RALPH_TASK_TIMEOUT", "1800")),
        idle_timeout=int(os.environ.get("RALPH_IDLE_TIMEOUT", "60")),
        heartbeat_interval=int(os.environ.get("RALPH_HEARTBEAT_INTERVAL", "30")),
        skip_dirty_check=os.environ.get("RALPH_SKIP_DIRTY_CHECK", ""),
        skip_precheck=os.environ.get("RALPH_SKIP_PRECHECK", ""),
        plan_pointer=plan_pointer,
        instance_slug=slug,
        work_dir=os.environ.get("RALPH_WORK_DIR", ""),
    )


def validate_plan(plan_path: Path) -> PlanFile:
    """Validate plan file exists and has checklist items. Raises SystemExit on failure."""
    if not plan_path.exists():
        die(f"Plan file not found: {plan_path}")
    plan = PlanFile(plan_path)
    if plan.total == 0:
        die("Plan has no checklist items. Add a ## Checklist section first.")
    return plan


def main():
    # Use git to find project root (handles symlinked scripts/ correctly)
    _git_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    if _git_root.returncode == 0 and _git_root.stdout.strip():
        PROJECT_ROOT = Path(_git_root.stdout.strip())
    else:
        PROJECT_ROOT = Path(__file__).resolve().parent.parent
    MAX_STALE = 3
    os.chdir(PROJECT_ROOT)

    # --- Configuration from env ---
    cfg = parse_config(sys.argv[1:])
    max_iterations = cfg.max_iterations
    plan_pointer = cfg.plan_pointer
    assert plan_pointer is not None
    task_timeout = cfg.task_timeout
    idle_timeout = cfg.idle_timeout
    heartbeat_interval = cfg.heartbeat_interval
    skip_dirty_check = cfg.skip_dirty_check
    skip_precheck = cfg.skip_precheck

    log_file = Path(".ralph-loop.log")
    lock = LockFile(Path(".ralph-loop.lock"))
    summary_file = Path("docs/plans/.ralph-result")

    child_proc_ref: list[subprocess.Popen | None] = [None]

    # --- Recursion guard ---
    if os.environ.get("_RALPH_LOOP_RUNNING"):
        die("Nested ralph loop detected — aborting to prevent recursion")
    os.environ["_RALPH_LOOP_RUNNING"] = "1"

    # --- Resolve active plan ---
    if not plan_pointer.exists():
        die("No active plan. Run @plan first to set docs/plans/.active")

    plan_path = Path(plan_pointer.read_text().strip())
    if not plan_path.exists():
        die(f"Plan file not found: {plan_path}")

    # --- Reject dirty working tree ---
    if not skip_dirty_check:
        r = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
        if r.stdout.strip():
            print("⚠️ Dirty working tree detected. Proceeding anyway (use RALPH_SKIP_DIRTY_CHECK=1 to silence).")

    # --- Verify checklist exists ---
    plan = validate_plan(plan_path)

    # --- Signal handling + cleanup ---
    shutdown_flag = [False]
    _cleanup_handler = make_cleanup_handler(child_proc_ref, lock, shutdown_flag=shutdown_flag)
    signal.signal(signal.SIGTERM, _cleanup_handler)
    signal.signal(signal.SIGINT, _cleanup_handler)
    atexit.register(lock.release)

    if not lock.try_acquire():
        die("Another ralph-loop is already running (lock held)")

    # --- Detect CLI once ---
    base_cmd = detect_cli()

    # --- Startup banner ---
    plan.reload()
    print(f"🔄 Ralph Loop — {plan.unchecked} tasks remaining", flush=True)

    # --- Main loop ---
    prev_checked = 0
    stale_rounds = 0
    last_reverted: list[tuple[int, str]] = []
    final_exit = 1
    prev_exit = -1  # -1 = no previous iteration; 0 = last CLI exited OK (precheck cacheable)

    for i in range(1, max_iterations + 1):
        plan.reload()

        if shutdown_flag[0]:
            break

        if plan.is_complete:
            if plan.is_all_skipped:
                print(f"⚠️ All tasks skipped — nothing completed", flush=True)
            else:
                print(f"✅ All {plan.checked} tasks complete!", flush=True)
            final_exit = 0
            break

        # Circuit breaker
        if plan.checked <= prev_checked and i > 1:
            stale_rounds += 1
            print(f"⚠️  No progress — retrying ({stale_rounds}/{MAX_STALE})", flush=True)
            if stale_rounds >= MAX_STALE:
                print(f"❌ Stuck — {MAX_STALE} retries with no progress. Stopping.", flush=True)
                for item in plan.next_unchecked(50):
                    print(f"   {item}")
                break
        else:
            stale_rounds = 0
        prev_checked = plan.checked



        # Build prompt
        if i == 1 and plan.checked == 0:
            prompt = build_prompt(i, plan, plan_path, PROJECT_ROOT, skip_precheck, is_first=True, stale_rounds=stale_rounds, log_path=log_file)
        else:
            prompt = build_prompt(i, plan, plan_path, PROJECT_ROOT, skip_precheck, stale_rounds=stale_rounds, log_path=log_file, reverted_items=last_reverted)

        if shutdown_flag[0]:
            break

        # Launch kiro-cli with PTY for unbuffered output + idle watchdog
        if base_cmd[0] == 'claude':
            cmd = [base_cmd[0], '-p', prompt] + base_cmd[2:]
        else:
            cmd = base_cmd + [prompt]

        proc, pty_stop = pty_run(cmd, log_file)
        child_proc_ref[0] = proc

        stop_event = threading.Event()
        hb = threading.Thread(
            target=_heartbeat,
            args=(proc, i, stop_event, plan, heartbeat_interval),
            kwargs={"log_path": log_file, "idle_timeout": idle_timeout},
            daemon=True,
        )
        hb.start()

        try:
            proc.wait(timeout=task_timeout)
        except subprocess.TimeoutExpired:
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"⏰ [{ts}] Timed out after {task_timeout}s — restarting", flush=True)
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                proc.wait()

        stop_event.set()
        hb.join(timeout=2)
        pty_stop()

        prev_exit = proc.returncode if proc.returncode is not None else 1

        if shutdown_flag[0]:
            break

        # Post-iteration: verify inline commands and revert false [x] marks
        plan.reload()
        reverted = plan.revert_failed_checks(cwd=str(PROJECT_ROOT), timeout=120)
        last_reverted = reverted
        if reverted:
            print(f"🔍 Reverted {len(reverted)} falsely checked items:", flush=True)
            for idx, cmd in reverted:
                print(f"   #{idx}: `{cmd}` failed", flush=True)

        # Early completion check — avoid wasting a full iteration
        plan.reload()
        if plan.is_complete:
            if plan.is_all_skipped:
                print(f"⚠️ All tasks skipped — nothing completed", flush=True)
            else:
                print(f"✅ All {plan.checked} tasks complete!", flush=True)
            final_exit = 0
            break

    else:
        plan.reload()
        if not plan.is_complete:
            print(f"\n⚠️ Reached max iterations ({max_iterations}). {plan.unchecked} items still unchecked.",
                  flush=True)

    write_summary(final_exit, plan, plan_path, summary_file)
    lock.release()
    sys.exit(final_exit)


if __name__ == "__main__":
    main()
