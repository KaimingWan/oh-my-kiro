#!/usr/bin/env python3
"""generate_configs.py — Single source of truth for CC + Kiro agent configs.

Replaces generate-platform-configs.sh. Outputs:
  .claude/settings.json
  .kiro/agents/{pilot,reviewer,researcher,executor}.json
"""
import argparse
import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_ROOT = Path(__file__).resolve().parent.parent  # Always points to OMCC repo

# ── Validation ───────────────────────────────────────────────────────────

def validate() -> int:
    """Check consistency between hook files and enforcement.md registry.

    Dispatcher scripts (hooks/dispatch-*.sh) are registered in generate_configs.py
    itself (as code), not in enforcement.md (which is human-maintained). Both sources
    are consulted so the registry stays consistent.
    """
    hooks_dir = PROJECT_ROOT / "hooks"
    enforcement_md = PROJECT_ROOT / ".kiro" / "rules" / "enforcement.md"

    # Collect .sh files on disk (exclude _lib/)
    on_disk = set()
    for sh_file in hooks_dir.rglob("*.sh"):
        rel = sh_file.relative_to(PROJECT_ROOT)
        if "_lib" not in rel.parts:
            on_disk.add(str(rel))

    # Source 1: enforcement.md hook registry table
    in_registry = set()
    text = enforcement_md.read_text()
    in_hook_registry = False
    for line in text.splitlines():
        if "## Hook Registry" in line:
            in_hook_registry = True
            continue
        if in_hook_registry and line.startswith("## "):
            break
        if in_hook_registry and "|" in line and "hooks/" in line and not line.startswith("|---"):
            match = re.search(r'`(hooks/[^`*]+\.sh)`', line)
            if match:
                in_registry.add(match.group(1))

    # Source 2: dispatcher files explicitly declared in this file (hooks/dispatch-*.sh).
    # Dispatchers are code-registered here rather than in enforcement.md (human doc).
    dispatcher_pattern = re.compile(r'"(hooks/dispatch-[^"]+\.sh)"')
    self_text = Path(__file__).read_text()
    for m in dispatcher_pattern.finditer(self_text):
        in_registry.add(m.group(1))

    # Source 3: overlay extra_hooks (project-specific hooks declared in .omcc-overlay.json)
    overlay_file = PROJECT_ROOT / ".omcc-overlay.json"
    if overlay_file.exists():
        import json
        try:
            overlay = json.loads(overlay_file.read_text())
            for event_hooks in overlay.get("extra_hooks", {}).values():
                for hook in event_hooks:
                    cmd = hook.get("command", hook) if isinstance(hook, dict) else hook
                    # Extract the hooks/... path from the command string
                    parts = cmd.split()
                    for part in parts:
                        if part.startswith("hooks/") and part.endswith(".sh"):
                            in_registry.add(part)
        except (json.JSONDecodeError, AttributeError):
            pass

    errors = 0
    # Files on disk but not registered
    for f in sorted(on_disk - in_registry):
        print(f"  ❌ On disk but not in enforcement.md: {f}")
        errors += 1
    # Registered but missing from disk
    for f in sorted(in_registry - on_disk):
        if (PROJECT_ROOT / f).exists():
            continue
        print(f"  ❌ In enforcement.md but not on disk: {f}")
        errors += 1

    if errors:
        print(f"\n❌ {errors} inconsistency(ies) found.")
        return 1
    print("✅ Hook registry is consistent with files on disk.")
    return 0


# ── Overlay support ───────────────────────────────────────────────────────

def load_overlay(overlay_path: Path, project_root: Path) -> tuple[list, dict]:
    """Load and validate .omcc-overlay.json, return (extra_skills, extra_hooks).

    extra_skills: list of skill paths (relative to project_root) whose SKILL.md exists
    extra_hooks: dict mapping event name to list of hook command dicts
    """
    if not overlay_path.exists():
        raise FileNotFoundError(f"Overlay file not found: {overlay_path}")

    try:
        data = json.loads(overlay_path.read_text())
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in overlay file {overlay_path}: {e}") from e

    extra_skills = data.get("extra_skills", [])
    extra_hooks = data.get("extra_hooks", {})

    # Validate extra_skills: each must have a SKILL.md
    for skill_path in extra_skills:
        skill_md = project_root / skill_path / "SKILL.md"
        if not skill_md.exists():
            raise ValueError(f"extra_skills path missing SKILL.md: {project_root / skill_path}")

    # Validate extra_hooks: event names must be valid camelCase Kiro hook types
    # Claude Code uses PascalCase (UserPromptSubmit), Kiro uses camelCase (userPromptSubmit)
    VALID_HOOK_EVENTS = {'agentSpawn', 'userPromptSubmit', 'preToolUse', 'postToolUse', 'stop'}
    for event in extra_hooks:
        if event not in VALID_HOOK_EVENTS:
            raise ValueError(
                f"Invalid hook event '{event}' in overlay extra_hooks. "
                f"Valid events: {', '.join(sorted(VALID_HOOK_EVENTS))}"
            )

    # Validate extra_hooks: each command path must exist
    for event, hooks in extra_hooks.items():
        for hook in hooks:
            cmd = hook.get("command", "")
            # Only validate paths (not echo/inline commands)
            cmd_path = project_root / cmd
            if not cmd.startswith("echo") and not cmd_path.exists():
                raise ValueError(f"extra_hooks command not found: {cmd_path}")

    return extra_skills, extra_hooks


# ── Shared hook definitions ──────────────────────────────────────────────

# Dispatcher paths (code-registered; also picked up by validate() regex)
DISPATCH_PRE_BASH = "hooks/dispatch-pre-bash.sh"
DISPATCH_PRE_WRITE = "hooks/dispatch-pre-write.sh"

SECURITY_HOOKS_BASH = [
    {"matcher": "execute_bash", "command": "hooks/security/block-dangerous.sh"},
    {"matcher": "execute_bash", "command": "hooks/security/block-secrets.sh"},
    {"matcher": "execute_bash", "command": "hooks/security/block-sed-json.sh"},
    {"matcher": "execute_bash", "command": "hooks/security/block-outside-workspace.sh"},
    {"matcher": "fs_write", "command": "hooks/security/block-outside-workspace.sh"},
]

SECURITY_HOOKS_CLAUDE = [
    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-dangerous.sh'},
    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-secrets.sh'},
    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-sed-json.sh'},
    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'},
]

DENIED_COMMANDS_STRICT = [
    r"rm\s+(-[rRf]|--recursive|--force).*",
    r"rmdir\b.*", r"mkfs\b.*", r"sudo\b.*",
    r"git\s+push\s+.*--force.*", r"git\s+reset\s+--hard.*", r"git\s+clean\s+-f.*",
    r"chmod\s+(-R\s+)?777.*",
    r"curl.*\|\s*(ba)?sh.*", r"wget.*\|\s*(ba)?sh.*",
    r"kill\s+-9.*", r"killall\b.*", r"shutdown\b.*", r"reboot\b.*",
    r"DROP\s+(DATABASE|TABLE|SCHEMA).*", r"TRUNCATE\b.*",
    r"find\b.*-delete", r"find\b.*-exec\s+rm",
]

DENIED_COMMANDS_SUBAGENT = [
    "git commit.*", "git push.*", "git checkout.*", "git reset.*", "git stash.*",
]

# Overlay uses camelCase (Kiro-native). Map to PascalCase for Claude Code.
CAMEL_TO_PASCAL = {
    "agentSpawn": "AgentSpawn",
    "userPromptSubmit": "UserPromptSubmit",
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "stop": "Stop",
}


# ── Config builders ──────────────────────────────────────────────────────

def claude_settings(extra_hooks: dict | None = None) -> dict:
    """Claude Code settings. Note: CC uses PascalCase hook events, Kiro uses camelCase."""
    settings = {
        "permissions": {"allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)"], "deny": []},
        "hooks": {
            "UserPromptSubmit": [{"hooks": [
                {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/correction-detect.sh'},
                {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/session-init.sh'},
                {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/context-enrichment.sh'},
            ]}],
            "PreToolUse": [
                {"matcher": "Bash", "hooks": SECURITY_HOOKS_CLAUDE + [
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/gate/enforce-ralph-loop.sh'},
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/gate/require-regression.sh'},
                ]},
                {"matcher": "Write|Edit", "hooks": [
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'},
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/gate/pre-write.sh'},
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/gate/enforce-ralph-loop.sh'},
                ]},
            ],
            "PostToolUse": [
                {"matcher": "Write|Edit", "hooks": [
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/post-write.sh'},
                ]},
                {"matcher": "Bash", "hooks": [
                    {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/post-bash.sh'},
                ]},
            ],
            "Stop": [{"hooks": [
                {"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/verify-completion.sh'},
            ]}],
        },
    }
    # Merge overlay extra_hooks (camelCase → PascalCase)
    # CC hooks use grouped structure: [{"matcher": "X", "hooks": [...]}, ...]
    # Kiro matcher names differ from CC (execute_bash→Bash, fs_write→Write|Edit)
    KIRO_TO_CC_MATCHER = {"execute_bash": "Bash", "fs_write": "Write|Edit"}
    for event, hook_list in (extra_hooks or {}).items():
        pascal_event = CAMEL_TO_PASCAL.get(event, event)
        if pascal_event not in settings["hooks"]:
            cc_hooks = [{"type": "command", "command": f'bash "$CLAUDE_PROJECT_DIR"/{h["command"]}'} for h in hook_list]
            settings["hooks"][pascal_event] = [{"hooks": cc_hooks}]
            continue
        for h in hook_list:
            cc_hook = {"type": "command", "command": f'bash "$CLAUDE_PROJECT_DIR"/{h["command"]}'}
            cc_matcher = KIRO_TO_CC_MATCHER.get(h.get("matcher", ""), "")
            # Find matching group or append to last non-matcher group
            placed = False
            for group in settings["hooks"][pascal_event]:
                if cc_matcher and group.get("matcher") == cc_matcher:
                    group["hooks"].append(cc_hook)
                    placed = True
                    break
            if not placed:
                # No matcher or no matching group — append to last group's hooks
                settings["hooks"][pascal_event][-1].setdefault("hooks", []).append(cc_hook)
    return settings


def _main_agent_resources(extra_skills: list | None = None) -> list:
    resources = [
        "file://AGENTS.md",
        "file://knowledge/INDEX.md",
        "skill://skills/planning/SKILL.md",
        "skill://skills/reviewing/SKILL.md",
    ]
    for skill_path in (extra_skills or []):
        resources.append(f"skill://{skill_path}/SKILL.md")
    return resources


def _build_main_agent(
    name: str,
    include_regression: bool = False,
    extra_skills: list | None = None,
    extra_hooks: dict | None = None,
) -> dict:
    pre_tool_use = SECURITY_HOOKS_BASH + [
        {"matcher": "fs_write", "command": "hooks/gate/pre-write.sh"},
        {"matcher": "execute_bash", "command": "hooks/gate/enforce-ralph-loop.sh"},
        {"matcher": "fs_write", "command": "hooks/gate/enforce-ralph-loop.sh"},
    ]
    if include_regression:
        pre_tool_use.append({"matcher": "execute_bash", "command": "hooks/gate/require-regression.sh"})
    hooks = {
        "userPromptSubmit": [
            {"command": "hooks/feedback/correction-detect.sh"},
            {"command": "hooks/feedback/session-init.sh"},
            {"command": "hooks/feedback/context-enrichment.sh"},
        ],
        "preToolUse": pre_tool_use,
        "postToolUse": [
            {"matcher": "fs_write", "command": "hooks/feedback/post-write.sh"},
            {"matcher": "execute_bash", "command": "hooks/feedback/post-bash.sh"},
        ],
        "stop": [{"command": "hooks/feedback/verify-completion.sh"}],
    }
    for event, hook_list in (extra_hooks or {}).items():
        hooks.setdefault(event, []).extend(hook_list)
    return {
        "name": name,
        "description": "Main orchestrator agent with deterministic workflow gates",
        "tools": ["*"],
        "allowedTools": ["*"],
        "resources": _main_agent_resources(extra_skills),
        "hooks": hooks,
        "toolsSettings": {
            "subagent": {
                "availableAgents": ["researcher", "reviewer", "executor"],
                "trustedAgents": ["researcher", "reviewer", "executor"],
            },
            "shell": {
                "autoAllowReadonly": True,
                "deniedCommands": DENIED_COMMANDS_STRICT,
            },
        },
    }


def default_agent(extra_skills: list | None = None, extra_hooks: dict | None = None) -> dict:
    return _build_main_agent("default", include_regression=False, extra_skills=extra_skills, extra_hooks=extra_hooks)


def pilot_agent(extra_skills: list | None = None, extra_hooks: dict | None = None) -> dict:
    return _build_main_agent("pilot", include_regression=True, extra_skills=extra_skills, extra_hooks=extra_hooks)


def reviewer_agent() -> dict:
    return {
        "name": "reviewer",
        "description": "Review expert. Plan review: challenge decisions, find gaps. Code review: check quality, security, SOLID.",
        "prompt": "file://../../agents/reviewer-prompt.md",
        "tools": ["read", "write", "shell"],
        "allowedTools": ["read", "write", "shell"],
        "resources": ["skill://skills/reviewing/SKILL.md"],
        "hooks": {
            "agentSpawn": [{"command": "echo '🔍 REVIEWER: Never skip analysis — always read the full plan/diff before giving verdict'"}],
            "preToolUse": SECURITY_HOOKS_BASH,
            "postToolUse": [{"matcher": "execute_bash", "command": "hooks/feedback/post-bash.sh"}],
            "stop": [{"command": "echo '📋 Review checklist: correctness, security, edge cases, test coverage?'"}],
        },
        "includeMcpJson": True,
        "toolsSettings": {
            "shell": {
                "autoAllowReadonly": True,
                "deniedCommands": ["git commit.*", "git push.*", "git checkout.*", "git reset.*"],
            },
        },
    }


def researcher_agent() -> dict:
    return {
        "name": "researcher",
        "description": "Research specialist. Web research via fetch MCP + code search via ripgrep MCP + Tavily via shell.",
        "prompt": "file://../../agents/researcher-prompt.md",
        "mcpServers": {
            "fetch": {"command": "uvx", "args": ["--with", "socksio", "mcp-server-fetch"]},
        },
        "tools": ["read", "shell", "@ripgrep", "@fetch"],
        "allowedTools": ["read", "shell", "@ripgrep", "@fetch"],
        "resources": ["skill://skills/research/SKILL.md"],
        "hooks": {
            "agentSpawn": [{"command": "echo '🔬 RESEARCHER: 1) Cite sources 2) Cross-verify claims 3) Report gaps explicitly'"}],
            "preToolUse": SECURITY_HOOKS_BASH,
            "postToolUse": [{"matcher": "execute_bash", "command": "hooks/feedback/post-bash.sh"}],
            "stop": [{"command": "echo '📝 Research complete. Did you: cite sources, cross-verify, report gaps?'"}],
        },
        "includeMcpJson": True,
        "toolsSettings": {
            "shell": {
                "autoAllowReadonly": True,
                "deniedCommands": ["git commit.*", "git push.*"],
            },
        },
    }


def executor_agent() -> dict:
    return {
        "name": "executor",
        "description": "Task executor for parallel plan execution. Implements code + runs verify. Does NOT edit plan files or git commit.",
        "tools": ["read", "write", "shell"],
        "allowedTools": ["read", "write", "shell"],
        "hooks": {
            "agentSpawn": [{"command": "echo '⚡ EXECUTOR: 1) Implement assigned task 2) Run verify command 3) Report result 4) Do NOT git commit or edit plan files'"}],
            "preToolUse": SECURITY_HOOKS_BASH,
            "postToolUse": [{"matcher": "execute_bash", "command": "hooks/feedback/post-bash.sh"}],
        },
        "includeMcpJson": True,
        "toolsSettings": {
            "shell": {
                "autoAllowReadonly": True,
                "deniedCommands": DENIED_COMMANDS_SUBAGENT,
            },
        },
    }


# ── Write configs ────────────────────────────────────────────────────────

def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def write_md(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def cc_reviewer_agent() -> str:
    prompt = (SCRIPT_ROOT / "agents" / "reviewer-prompt.md").read_text()
    return f"""---
name: reviewer
description: "Review expert. Plan review: challenge decisions, find gaps. Code review: check quality, security, SOLID."
tools: Read, Write, Bash, Grep, Glob
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-dangerous.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-secrets.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-sed-json.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/post-bash.sh'
  Stop:
    - hooks:
        - type: command
          command: 'echo "📋 Review checklist: correctness, security, edge cases, test coverage?"'
---

{prompt}
"""


def cc_researcher_agent() -> str:
    prompt = (SCRIPT_ROOT / "agents" / "researcher-prompt.md").read_text()
    return f"""---
name: researcher
description: "Research specialist. Web research via fetch MCP + code search via ripgrep MCP + Tavily via shell."
tools: Read, Bash, Grep, Glob, WebSearch, WebFetch
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-dangerous.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-secrets.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-sed-json.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/post-bash.sh'
  Stop:
    - hooks:
        - type: command
          command: 'echo "📝 Research complete. Did you: cite sources, cross-verify, report gaps?"'
---

{prompt}
"""


def cc_executor_agent() -> str:
    return """---
name: executor
description: "Task executor for parallel plan execution. Implements code + runs verify. Does NOT edit plan files or git commit."
tools: Read, Write, Edit, Bash, Grep, Glob
permissionMode: bypassPermissions
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-dangerous.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-secrets.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-sed-json.sh'
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/security/block-outside-workspace.sh'
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR"/hooks/feedback/post-bash.sh'
---

⚡ EXECUTOR: 1) Implement assigned task 2) Run verify command 3) Report result 4) Do NOT git commit or edit plan files
"""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate CC + Kiro agent configs.")
    parser.add_argument("--project-root", type=Path, default=None,
                        help="Project root directory (default: repo root)")
    parser.add_argument("--overlay", type=Path, default=None,
                        help="Path to .omcc-overlay.json with extra_skills/extra_hooks")
    parser.add_argument("--skip-validate", action="store_true",
                        help="Skip hook registry validation (for use with external --project-root)")
    parser.add_argument("--validate", action="store_true",
                        help="Only run validation, do not generate configs")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    global PROJECT_ROOT

    args = parse_args(argv)

    if args.project_root is not None:
        PROJECT_ROOT = args.project_root.resolve()

    if args.validate:
        return validate()

    if not args.skip_validate:
        if validate() != 0:
            print("\n🚫 Fix inconsistencies before generating configs.")
            return 1

    # Load overlay if provided
    extra_skills: list = []
    extra_hooks: dict = {}
    if args.overlay is not None:
        try:
            extra_skills, extra_hooks = load_overlay(args.overlay, PROJECT_ROOT)
        except (FileNotFoundError, ValueError) as e:
            print(f"❌ Overlay error: {e}")
            return 1

    print("🔧 Generating platform configs from unified source...")

    targets = [
        (PROJECT_ROOT / ".claude" / "settings.json", claude_settings(extra_hooks)),
        (PROJECT_ROOT / ".kiro" / "agents" / "default.json", default_agent(extra_skills, extra_hooks)),
        (PROJECT_ROOT / ".kiro" / "agents" / "pilot.json", pilot_agent(extra_skills, extra_hooks)),
        (PROJECT_ROOT / ".kiro" / "agents" / "reviewer.json", reviewer_agent()),
        (PROJECT_ROOT / ".kiro" / "agents" / "researcher.json", researcher_agent()),
        (PROJECT_ROOT / ".kiro" / "agents" / "executor.json", executor_agent()),
    ]

    errors = 0
    for path, data in targets:
        write_json(path, data)
        # Validate by re-reading
        try:
            json.loads(path.read_text())
            print(f"  ✅ {path.relative_to(PROJECT_ROOT)}")
        except json.JSONDecodeError:
            print(f"  ❌ INVALID JSON: {path.relative_to(PROJECT_ROOT)}")
            errors += 1

    # CC agent markdown files
    cc_targets = [
        (PROJECT_ROOT / ".claude" / "agents" / "reviewer.md", cc_reviewer_agent()),
        (PROJECT_ROOT / ".claude" / "agents" / "researcher.md", cc_researcher_agent()),
        (PROJECT_ROOT / ".claude" / "agents" / "executor.md", cc_executor_agent()),
    ]
    for path, content in cc_targets:
        write_md(path, content)
        print(f"  ✅ {path.relative_to(PROJECT_ROOT)}")

    if errors:
        print(f"\n❌ {errors} config(s) have invalid JSON!")
        return 1

    print("\n✅ All configs generated and validated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
