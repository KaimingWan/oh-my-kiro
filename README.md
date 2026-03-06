# oh-my-kiro
[![Release](https://img.shields.io/github/v/release/KaimingWan/oh-my-kiro?include_prereleases)](https://github.com/KaimingWan/oh-my-kiro/releases)

**Turn your AI coding agent into a self-evolving, personalized super-intelligence.**

Like oh-my-zsh for Zsh, but for AI coding agents. A framework that makes your agent learn from every interaction, persist valuable knowledge, and get stronger over time — automatically.

Works with: **Kiro CLI**

---

## The Problem

You use AI coding agents every day. But every new session starts from zero. The agent forgets your preferences, repeats the same mistakes, loses valuable context, and never truly understands your workflow.

**What if your agent could compound its intelligence over time?**

## The Philosophy

### 🔒 Deterministic Over Hopeful

> If it can be enforced by code, don't enforce it with words.

Natural language instructions drift. Hooks don't. This framework uses a **3-layer determinism model**:

| Layer | Mechanism | Certainty |
|-------|-----------|-----------|
| L1 Commands | `@plan` `@execute` `@research` `@review` `@cpu` `@skill` `@lint` | 100% — user triggers full workflow |
| L2 Gates | `hooks/gate/` + `hooks/security/` (PreToolUse exit 2) | 100% — hard block, agent cannot bypass |
| L3 Feedback | `hooks/feedback/` (PostToolUse/Stop/UserPromptSubmit) | ~50% — advisory, agent may ignore |

### 🔄 Compound Interest Engineering

> Every interaction should make the agent permanently smarter.

The agent captures corrections in real-time and writes them to persistent files. Day 1 it's generic. Day 30 it knows your codebase, your style, your decision patterns.

### 💾 Auto-Persist Valuable Results

> If it's worth generating, it's worth saving.

Research findings → `knowledge/`. Plans → `docs/plans/`. Lessons → `knowledge/rules.md` + `knowledge/episodes.md`. Nothing valuable is lost in chat.

### 🧠 Feedback Loop → Self-Evolution

> The agent detects your corrections and rewires itself.

When you say "no, use X not Y", the agent captures the pattern and writes it to the appropriate file. Next session, it won't need correcting.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  L1: Commands (User-Triggered, 100% Deterministic)       │
│  @plan · @execute · @research · @review · @cpu           │
│  @lint · @skill                                          │
│  Each hardcodes the full workflow — no steps skipped.    │
├─────────────────────────────────────────────────────────┤
│  L2: Gates & Security (PreToolUse, 100% Hard Block)      │
│  pre-write · enforce-ralph-loop · enforce-work-dir       │
│  require-regression · block-dangerous · block-secrets    │
│  block-sed-json · block-outside-workspace                │
├─────────────────────────────────────────────────────────┤
│  L3: Feedback (PostToolUse/Stop/UserPromptSubmit)        │
│  post-write (lint+test+OV) · post-bash (verify-log+OV)  │
│  verify-completion · correction-detect · auto-capture    │
│  session-init · context-enrichment · kb-health-report    │
├─────────────────────────────────────────────────────────┤
│  Skills (On-Demand, 10 core)                             │
│  planning · reviewing · debugging · research             │
│  verification · finishing · self-reflect · find-skills   │
│  agent · know                                            │
├─────────────────────────────────────────────────────────┤
│  Subagents (Task Isolation, 3 specialists)               │
│  reviewer · researcher · executor                        │
├─────────────────────────────────────────────────────────┤
│  Knowledge (Persistent Memory + OV Semantic Search)      │
│  rules.md · episodes.md · INDEX.md routing               │
│  OpenViking daemon for semantic recall                   │
└─────────────────────────────────────────────────────────┘
```

## Custom Commands

The primary way to trigger workflows deterministically. Each command hardcodes the full step chain — the agent cannot skip steps.

| Command | Workflow |
|---------|----------|
| `@plan` | Deep understanding (Phase 0) → write plan with TDD checklist → dispatch 4 reviewer subagents → fix until APPROVE → user confirm |
| `@execute` | Load approved plan → Ralph Loop: outer Python loop checks checklist → fresh CLI per iteration → circuit breaker (3 stalls) → auto-launched from `@plan` |
| `@research` | L0 built-in knowledge → L1 web search → L2 deep research → write findings to file |
| `@review` | Dispatch reviewer subagent → categorize P0-P3 → cite file:line |
| `@cpu` | Commit all changes → push to remote → detect worktree → merge or create PR |
| `@lint` | Health check: instruction file line count, rules file sizes, duplication detection, sync verification |
| `@skill` | List all skills with descriptions, match user need to closest skill |

## Hook System

### L2: Hard Gates (PreToolUse — exit 2 = blocked)

| Hook | What It Does |
|------|-------------|
| `gate/pre-write.sh` | Instruction file write protection + brainstorming gate for plan creation + plan structure validation |
| `gate/enforce-ralph-loop.sh` | Blocks direct source edits when an active plan exists — forces execution through Ralph Loop |
| `gate/enforce-work-dir.sh` | Restricts file writes to the plan's declared Work Dir during execution |
| `gate/require-regression.sh` | Blocks checklist check-off for ralph_loop/lib changes without regression tests |
| `security/block-dangerous.sh` | Blocks `rm -rf`, `sudo`, `curl\|bash`, force push, etc. |
| `security/block-secrets.sh` | Scans for API keys, private keys before git commit/push |
| `security/block-sed-json.sh` | Blocks sed/awk on JSON files — use jq instead |
| `security/block-outside-workspace.sh` | Blocks file operations outside the project workspace |

### L3: Feedback (PostToolUse/Stop/UserPromptSubmit — advisory)

| Hook | What It Does |
|------|-------------|
| `feedback/post-write.sh` | Merged hook: auto-lint + auto-test (30s debounce) + OV index for knowledge files |
| `feedback/post-bash.sh` | Logs command execution for verify evidence + OV sync for knowledge file changes |
| `feedback/verify-completion.sh` | Stop hook: checks plan checklist + re-runs all verify commands |
| `feedback/correction-detect.sh` | Detects user corrections in prompt text |
| `feedback/auto-capture.sh` | Captures corrections → writes to episodes.md + syncs to OV |
| `feedback/session-init.sh` | Episode cleanup + promotion reminder + OV daemon auto-start + knowledge sync (once per session) |
| `feedback/context-enrichment.sh` | Rules injection (keyword-matched) + episode hints + OV semantic search + skill routing reminders |
| `feedback/kb-health-report.sh` | Knowledge base quality report: cap warnings, promotion candidates |

### Dispatchers

| Hook | What It Does |
|------|-------------|
| `dispatch-pre-write.sh` | Routes fs_write events to security + gate hooks in order |
| `dispatch-pre-bash.sh` | Routes execute_bash events to security + gate hooks in order |

### Shared Libraries (`hooks/_lib/`)

| Library | Purpose |
|---------|---------|
| `common.sh` | `hook_block()`, `file_mtime()`, `detect_test_command()`, `is_source_file()`, `find_active_plan()` |
| `patterns.sh` | Regex patterns for file classification |
| `distill.sh` | Episode → rule promotion, section cap enforcement, archive cleanup |
| `ov-init.sh` | OpenViking client: `ov_init()`, `ov_search()`, `ov_add()`, `ov_session_commit()` |
| `block-recovery.sh` | Recovery from hook-blocked operations |

## Skills (10 Core)

| Skill | Purpose |
|-------|---------|
| `planning` | Full plan lifecycle: Phase 0 (deep understanding) → Phase 1 (write plan with TDD) → Phase 1.5 (4-reviewer parallel review) → Phase 2 (Ralph Loop execution) |
| `reviewing` | Code and plan review — multi-angle dispatch, P0-P3 categorization, file:line citations |
| `debugging` | Systematic: reproduce → hypothesize → verify → fix (with LSP-first rule) |
| `research` | Multi-level: L0 built-in → L1 web search → L2 deep research → persist findings |
| `verification` | Evidence before completion claims — no shortcuts |
| `finishing` | Branch completion: merge / PR / keep / discard + worktree cleanup |
| `self-reflect` | Capture corrections → extract insight → dedup check → append to episodes.md |
| `find-skills` | Discover available skills and match to user needs |
| `agent` | Codify agent identity and principles into AGENTS.md |
| `know` | Persist knowledge discoveries to knowledge/ files |

## Subagents (3 Specialists)

| Agent | Role | Config |
|-------|------|--------|
| `reviewer` | Plan & code review — must cite file:line, never rubber-stamp | `.kiro/agents/reviewer.json` |
| `researcher` | Web research + code search — cite sources, cross-verify | `.kiro/agents/researcher.json` |
| `executor` | Task execution within Ralph Loop — fresh context per iteration | `.kiro/agents/executor.json` |

Additional configs: `pilot.json` (main orchestrator with all hooks wired) and `default.json` (fallback, same as pilot).

## Knowledge System

### Persistent Memory

| File | Purpose |
|------|---------|
| `knowledge/INDEX.md` | Routing table: question type → source file |
| `knowledge/rules.md` | Keyword-sectioned rules, injected per-message by topic match (🔴 critical = always, 🟡 relevant = keyword-matched) |
| `knowledge/episodes.md` | Mistakes and wins timeline (auto-cleanup on promotion, 30-entry cap) |
| `knowledge/reference/` | Archived skill content (writing style, mermaid, java, etc.) |

### OpenViking Semantic Search (Optional)

When configured via `.omk-overlay.json`, the framework uses OpenViking for semantic knowledge recall:

- **Auto-indexing**: knowledge files are automatically synced to OV on every write (fs_write, execute_bash, or session startup)
- **Semantic recall**: context-enrichment hook queries OV on every user prompt, injecting relevant knowledge snippets
- **Daemon**: `scripts/ov-daemon.py` runs as a background process, communicating via Unix socket
- **Degradation alert**: if OV is unavailable, hooks emit `⚠️ OV unavailable` instead of silently degrading

## Ralph Loop

The execution engine for approved plans. A Python outer loop (`scripts/ralph_loop.py`) that:

1. Reads the plan's `## Checklist` section
2. Spawns a fresh CLI instance (Kiro or Kiro) per iteration
3. Each iteration works on unchecked items until context fills up
4. Verifies checklist items by running their inline verify commands
5. Reverts any `- [x]` items whose verify commands fail
6. Circuit breaker: exits after 3 consecutive rounds with no progress
7. Prints a full summary on exit (completed / remaining / skipped)

## Project Structure

```
.
├── AGENTS.md                      # Agent identity, principles, skill routing
├── hooks/                         # Unified hook source (single truth)
│   ├── _lib/                      # common.sh, patterns.sh, distill.sh, ov-init.sh
│   ├── security/                  # block-dangerous, block-secrets, block-sed-json, block-outside-workspace
│   ├── gate/                      # pre-write, enforce-ralph-loop, enforce-work-dir, require-regression
│   └── feedback/                  # post-write, post-bash, verify-completion, correction-detect,
│                                  # auto-capture, session-init, context-enrichment, kb-health-report
├── skills/                        # 10 core skills (each has SKILL.md)
├── agents/                        # Subagent prompt files
├── commands/                      # Custom commands (@plan, @execute, @review, @research, @cpu, @lint, @skill)
├── scripts/
│   ├── ralph_loop.py              # Ralph Loop: Python outer loop for plan execution
│   ├── generate_configs.py        # Single source → CC + Kiro configs
│   ├── ov-daemon.py               # OpenViking semantic search daemon
│   └── lib/                       # Shared Python modules (plan.py, cli_detect.py, etc.)
├── tools/                         # CLI tools
│   ├── init-project.sh            # Bootstrap OMK into existing project
│   ├── install-skill.sh           # Install individual skills
│   ├── sync-omk.sh               # Sync upstream OMK changes
│   ├── validate-project.sh        # Validate project setup
│   └── audit-skills.sh            # Audit skill integrity
├── .claude/                       # Generated CC config
│   ├── settings.json              # Generated by scripts/generate_configs.py
│   └── rules/                     # security, shell, workflow, subagent, debugging, git-workflow, testing, code-quality
├── .kiro/                         # Generated Kiro config
│   ├── agents/*.json              # pilot, reviewer, researcher, executor, default
│   └── rules/                     # enforcement, commands, reference, code-analysis
├── knowledge/                     # Persistent memory
│   ├── INDEX.md                   # Knowledge routing table
│   ├── rules.md                   # Keyword-section rules (smart injection)
│   ├── episodes.md                # Mistakes and wins (auto-cleanup)
│   └── reference/                 # Archived reference materials
└── docs/
    ├── designs/                   # Design documents
    ├── plans/                     # Implementation plans (.active pointer)
    └── releases/                  # Release notes
```

Key design: `hooks/`, `skills/`, `agents/`, `commands/` are the single source of truth. Platform configs (`.claude/`, `.kiro/`) are generated by `scripts/generate_configs.py`.

## Compatibility

| Platform | Hooks | Commands | Skills | Subagents | Agent Configs |
|----------|-------|----------|--------|-----------|---------------|
| **Kiro** | ✅ Full | Via slash commands | ✅ | ✅ Full | `.claude/agents/*.md` (YAML frontmatter) |
| **Kiro CLI** | ✅ 5 events (preToolUse, postToolUse, userPromptSubmit, stop, agentSpawn) | ✅ `.kiro/prompts/` | ✅ | ✅ With constraints | `.kiro/agents/*.json` |

### Kiro Support

Full Kiro support via `scripts/generate_configs.py`:
- Agent configs: `.claude/agents/{reviewer,researcher,executor}.md` with YAML frontmatter + inlined prompts
- Hook wiring: `.claude/settings.json` with `$CLAUDE_PROJECT_DIR` paths
- Ralph loop: auto-detects `claude` CLI and uses `claude -p` with appropriate `--allowedTools`
- `stop_hook_active` handling: verify-completion.sh exits immediately on recursive stop

## Quick Start

### Clone and customize

```bash
git clone https://github.com/KaimingWan/oh-my-kiro.git my-project
cd my-project
python3 scripts/generate_configs.py  # Generate platform configs
# Edit AGENTS.md — define your agent's identity
# Start chatting — the agent evolves from here
```

### Add to existing project

```bash
git clone https://github.com/KaimingWan/oh-my-kiro.git /tmp/omk
/tmp/omk/tools/init-project.sh ./my-project "My Project"
```

### Cherry-pick

| Want | Copy |
|------|------|
| Just hooks | `hooks/` + run `scripts/generate_configs.py` |
| Just self-learning | `skills/self-reflect/` + `knowledge/rules.md` + `knowledge/episodes.md` |
| Just knowledge system | `knowledge/` + `hooks/_lib/ov-init.sh` + `scripts/ov-daemon.py` |
| Just subagents | `agents/` + `.kiro/agents/` |
| Just Ralph Loop | `scripts/ralph_loop.py` + `scripts/lib/` |

## Design Principles

1. **Deterministic over hopeful** — Commands and hard blocks, not soft prompts
2. **Compound over time** — Every session makes the next one better
3. **Single source of truth** — `hooks/`, `skills/`, `commands/` → generate platform configs
4. **Code over prose** — Hooks enforce, words suggest
5. **Evidence before claims** — Verification first, always
6. **No hacky workarounds** — Fix root causes, not symptoms
7. **Bold reform over timid patches** — Quality over backward compatibility

## License

MIT
