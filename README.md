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
┌──────────────────────────────────────────────────────────┐
│  L1: Commands (User-Triggered, 100% Deterministic)        │
│  @plan · @auto · @execute · @do · @research · @review     │
│  @cpu · @cpr · @ck · @wt · @lint · @skill                 │
│  Each hardcodes the full workflow — no steps skipped.     │
├──────────────────────────────────────────────────────────┤
│  L2: Gates & Security (PreToolUse, 100% Hard Block)       │
│  pre-write · enforce-ralph-loop · enforce-work-dir        │
│  require-regression · block-dangerous · block-secrets     │
│  block-sed-json · block-outside-workspace                 │
├──────────────────────────────────────────────────────────┤
│  L3: Feedback (PostToolUse/Stop/UserPromptSubmit)         │
│  post-write (lint+test+OV) · post-bash (verify-log+OV)   │
│  verify-completion · correction-detect · auto-capture     │
│  session-init · context-enrichment · kb-health-report     │
├──────────────────────────────────────────────────────────┤
│  Skills (On-Demand, 13 core)                              │
│  planning · reviewing · coding · debugging · research     │
│  verification · finishing · self-reflect · context7-docs  │
│  skill-creation · youtube · agent · know                  │
├──────────────────────────────────────────────────────────┤
│  Skill Security (Supply Chain Hardening)                   │
│  audit-skill.sh — 8-category threat scan                  │
│  install-skill.sh — audit gate before registration        │
│  patterns.sh — block bare npx skill installation          │
├──────────────────────────────────────────────────────────┤
│  Subagents (Task Isolation, 3 specialists)                │
│  reviewer · researcher · executor                         │
├──────────────────────────────────────────────────────────┤
│  Knowledge (Persistent Memory + OV Semantic Search)       │
│  rules.md · episodes.md · INDEX.md routing                │
│  OpenViking daemon for semantic recall                    │
└──────────────────────────────────────────────────────────┘
```

## Custom Commands

The primary way to trigger workflows deterministically. Each command hardcodes the full step chain — the agent cannot skip steps.

Commands come in two flavors:
- **Dual-mode** — available both as `@command` (in AGENTS.md) and as MCP prompt `@o/command <args>` (can accept inline arguments)
- **Command-only** — only available as `@command` in chat, no MCP prompt variant

### Dual-mode Commands (command + MCP prompt)

These can be invoked as `@command` or via MCP prompt `@o/command <your input>`:

| Command | MCP Prompt | Workflow |
|---------|-----------|----------|
| `@plan` | `@o/plan` | Deep understanding (Phase 0) → write plan with TDD checklist → dispatch reviewer subagents → fix until APPROVE → user confirm → Ralph Loop |
| `@auto` | `@o/auto` | Fully automated `@plan`: autonomous understanding (no user Q&A) → plan → review (auto-fix up to 2 rounds) → execute |
| `@research` | `@o/research` | L0 built-in knowledge → L1 web search → L2 deep research → write findings to file |
| `@review` | `@o/review` | Dispatch reviewer subagent → categorize P0-P3 → cite file:line |
| `@cpr` | `@o/cpr` | Commit → push → create Pull Request → worktree cleanup |
| `@ck` | `@o/ck` | Checkout branch into submodule worktree (fuzzy search support) |
| `@do` | `@o/do` | Lightweight task (< 1 hour): scratchpad → implement → verify. No plan file, no review dispatch |
| `@agent` | `@o/agent` | Distill a top-level principle into `knowledge/rules.md` |
| `@know` | `@o/know` | Capture knowledge insight into `knowledge/episodes.md` |

### Command-only (no MCP prompt)

| Command | Workflow |
|---------|----------|
| `@execute` | Load approved plan → Ralph Loop: outer Python loop checks checklist → fresh CLI per iteration → circuit breaker (3 stalls) |
| `@cpu` | Commit → push → detect worktree → merge or create PR (no PR creation, direct merge focus) |
| `@wt` | List all worktrees with status, clean up merged branches |
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
| `security/block-dangerous.sh` | Blocks `rm -rf`, `sudo`, `curl\|bash`, bare `npx skills add`, etc. |
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
| `patterns.sh` | Regex patterns for dangerous commands, injection detection, secret detection |
| `distill.sh` | Episode → rule promotion, section cap enforcement, archive cleanup |
| `ov-init.sh` | OpenViking client: `ov_init()`, `ov_search()`, `ov_add()`, `ov_session_commit()` |
| `block-recovery.sh` | Recovery from hook-blocked operations |

## Skills (13 Core)

| Skill | Purpose |
|-------|---------|
| `planning` | Full plan lifecycle: Phase 0 (deep understanding) → Phase 1 (write plan with TDD) → Phase 1.5 (4-reviewer parallel review) → Phase 2 (Ralph Loop execution) |
| `reviewing` | Code and plan review — multi-angle dispatch, P0-P3 categorization, file:line citations |
| `coding` | Coding best practices enforcement: LSP init, TDD red-green-refactor, minimal changes, self-review, verification |
| `debugging` | Systematic: reproduce → hypothesize → verify → fix (with LSP-first rule) |
| `research` | Multi-level: L0 built-in → L1 web search → L2 deep research → persist findings |
| `verification` | Evidence before completion claims — no shortcuts |
| `finishing` | Branch completion: merge / PR / keep / discard + worktree cleanup |
| `self-reflect` | Capture corrections → extract insight → dedup check → append to episodes.md |
| `context7-docs` | Fetch current library/framework documentation via Context7 MCP |
| `skill-creation` | Create production-ready skills from scratch: template, audit, register |
| `youtube` | Extract and summarize YouTube video content via subtitle extraction |
| `agent` | Distill top-level principles into knowledge/rules.md |
| `know` | Capture knowledge discoveries into knowledge/episodes.md |

## Skill Security

Agent skills are a supply chain attack surface. Based on [Snyk's ToxicSkills research](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/) (Feb 2026: 36.82% of public skills have security issues), OMK enforces a multi-layer defense:

| Layer | Mechanism | What It Catches |
|-------|-----------|-----------------|
| `audit-skill.sh` | 8-category threat scan | Prompt injection, malicious code, credential theft, base64 obfuscation, secret leaks, suspicious downloads |
| `install-skill.sh` | Audit gate before registration | Blocks CRITICAL skills, warns on HIGH, auto-removes failed skills |
| `sync-omk.sh` | Audit during framework sync | Blocks compromised skills from propagating to downstream projects |
| `patterns.sh` | Hook hard block | Prevents bare `npx skills add` — forces all installs through `install-skill.sh` |

### Threat Categories (based on Snyk ToxicSkills taxonomy)

| Category | Severity | Examples |
|----------|----------|---------|
| Prompt Injection | 🔴 CRITICAL | "ignore previous instructions", base64 obfuscation, Unicode smuggling, DAN jailbreaks |
| Malicious Code | 🔴 CRITICAL | eval/exec, shell=True, backdoors |
| Suspicious Downloads | 🔴 CRITICAL | curl\|bash, password-protected archives |
| Credential Handling | 🟠 HIGH | Reading ~/.aws/credentials, echoing API keys |
| Secret Detection | 🟠 HIGH | Hardcoded AWS keys, GitHub tokens, private keys |
| Third-Party Content | 🟡 MEDIUM | External HTTP fetches (indirect injection vector) |
| Unverifiable Dependencies | 🟡 MEDIUM | Runtime remote loading, dynamic imports |
| Excessive Permissions | 🟡 MEDIUM | sudo, systemctl modifications |

Run manually: `bash tools/audit-skill.sh <SKILL_DIR>`

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
| `knowledge/reference/` | Reference materials (writing style, java coding standards, etc.) |

### OpenViking Semantic Search (Optional)

When configured via `.omk-overlay.json`, the framework uses OpenViking for semantic knowledge recall:

- **Auto-indexing**: knowledge files are automatically synced to OV on every write
- **Semantic recall**: context-enrichment hook queries OV on every user prompt, injecting relevant knowledge snippets
- **Daemon**: `scripts/ov-daemon.py` runs as a background process, communicating via Unix socket
- **Degradation alert**: if OV is unavailable, hooks emit `⚠️ OV unavailable` instead of silently degrading

## Ralph Loop

The execution engine for approved plans. A Python outer loop (`scripts/ralph_loop.py`) that:

1. Reads the plan's `## Checklist` section
2. Spawns a fresh CLI instance per iteration
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
├── skills/                        # 11 core skills (each has SKILL.md)
├── agents/                        # Subagent prompt files
├── commands/                      # Custom commands (@plan, @execute, @review, @research, @cpu, @lint, @skill)
├── scripts/
│   ├── ralph_loop.py              # Ralph Loop: Python outer loop for plan execution
│   ├── generate_configs.py        # Single source → Kiro configs
│   ├── ov-daemon.py               # OpenViking semantic search daemon
│   └── lib/                       # Shared Python modules (plan.py, cli_detect.py, etc.)
├── tools/                         # CLI tools
│   ├── init-project.sh            # Bootstrap OMK into existing project
│   ├── install-skill.sh           # Install skill with security audit gate
│   ├── audit-skill.sh             # 8-category skill security audit
│   ├── sync-omk.sh               # Sync upstream OMK changes + skill sync
│   └── validate-project.sh        # Validate project setup
├── .kiro/                         # Generated Kiro config
│   ├── agents/*.json              # pilot, reviewer, researcher, executor, default
│   ├── rules/                     # enforcement, commands, reference, code-analysis
│   └── settings/                  # lsp.json, mcp.json
├── knowledge/                     # Persistent memory
│   ├── INDEX.md                   # Knowledge routing table
│   ├── rules.md                   # Keyword-section rules (smart injection)
│   ├── episodes.md                # Mistakes and wins (auto-cleanup)
│   └── reference/                 # Reference materials
└── docs/
    ├── designs/                   # Design documents
    ├── plans/                     # Implementation plans (.active pointer)
    └── releases/                  # Release notes
```

Key design: `hooks/`, `skills/`, `agents/`, `commands/` are the single source of truth. Platform configs are generated by `scripts/generate_configs.py`.

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
git submodule add https://github.com/KaimingWan/oh-my-kiro.git oh-my-kiro
bash oh-my-kiro/tools/init-project.sh . "My Project"
```

### Sync updates

```bash
bash oh-my-kiro/tools/sync-omk.sh .
```

This updates the submodule, syncs skills (with security audit), rules, configs, and AGENTS.md sections.

### Cherry-pick

| Want | Copy |
|------|------|
| Just hooks | `hooks/` + run `scripts/generate_configs.py` |
| Just self-learning | `skills/self-reflect/` + `knowledge/rules.md` + `knowledge/episodes.md` |
| Just knowledge system | `knowledge/` + `hooks/_lib/ov-init.sh` + `scripts/ov-daemon.py` |
| Just skill security | `tools/audit-skill.sh` + `tools/install-skill.sh` |
| Just Ralph Loop | `scripts/ralph_loop.py` + `scripts/lib/` |

## Extending OMK

See [EXTENSION-GUIDE.md](docs/EXTENSION-GUIDE.md) for adding project-specific skills, hooks, and knowledge.

## Design Principles

1. **Deterministic over hopeful** — Commands and hard blocks, not soft prompts
2. **Compound over time** — Every session makes the next one better
3. **Single source of truth** — `hooks/`, `skills/`, `commands/` → generate platform configs
4. **Code over prose** — Hooks enforce, words suggest
5. **Evidence before claims** — Verification first, always
6. **No hacky workarounds** — Fix root causes, not symptoms
7. **Bold reform over timid patches** — Quality over backward compatibility
8. **Secure by default** — All skill installs audited, dangerous commands blocked

## License

MIT
