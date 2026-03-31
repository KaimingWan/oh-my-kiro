# oh-my-kiro

[![Release](https://img.shields.io/github/v/release/KaimingWan/oh-my-kiro)](https://github.com/KaimingWan/oh-my-kiro/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests: 56](https://img.shields.io/badge/tests-56_passing-green)]()

**Your AI agent forgets everything. Mine doesn't.**

oh-my-kiro is a framework that gives your AI coding agent persistent memory, deterministic workflows, and self-evolving intelligence. Like oh-my-zsh for Zsh — but for AI agents.

_Day 1: generic agent. Day 30: knows your codebase, your style, your decision patterns._

Works with: **Kiro CLI**

[Quick Start](#quick-start) • [Why OMK](#why-oh-my-kiro) • [Commands](#commands) • [Architecture](#architecture)

---

## Quick Start

**New project:**
```bash
git clone https://github.com/KaimingWan/oh-my-kiro.git my-project
cd my-project
python3 scripts/generate_configs.py
```

**Existing project:**
```bash
git submodule add https://github.com/KaimingWan/oh-my-kiro.git oh-my-kiro
bash oh-my-kiro/tools/init-project.sh . "My Project"
```

**Start building:**
```
@auto build a REST API for user management
```

That's it. The agent understands requirements, writes a plan, reviews it, and executes — all autonomously.

---

## Why oh-my-kiro?

### The Core Problem: AI Agents Hallucinate and Drift

You tell the agent "always run tests before committing." It does — for 3 turns. Then it forgets. Or it "runs" tests by printing "tests passed" without actually executing anything. Or it skips the step because "the change is trivial."

**Natural language instructions are unreliable.** The agent interprets them probabilistically. It might follow them. It might not. You can't build a reliable workflow on "might."

### The Solution: As-Code, Hook-Based Enforcement

OMK's design philosophy: **if it can be enforced by code, don't enforce it with words.**

- ❌ Prompt: "Never commit secrets" → agent might still do it
- ✅ Hook: `block-secrets.sh` scans every `git push` → exit 2 = blocked. Zero exceptions.

- ❌ Prompt: "Always run tests after editing" → agent skips when context is tight
- ✅ Hook: `post-write.sh` auto-triggers lint + test on every file save. Agent doesn't choose.

- ❌ Prompt: "Follow the plan step by step" → agent jumps ahead or skips steps
- ✅ Hook: `enforce-ralph-loop.sh` blocks direct source edits when a plan exists. Must go through Ralph Loop.

This is not about restricting the agent. It's about **raising the success rate of every operation** by removing the possibility of hallucinated shortcuts.

### What You Get

- **Agent never forgets** — Corrections persist across sessions. Mistakes become rules. Knowledge compounds.
- **19 hooks enforce, not suggest** — The agent literally cannot `rm -rf /`, commit secrets, skip tests, or edit files outside its workspace.
- **Agent crashes don't matter** — Ralph Loop keeps spawning fresh agents until every checklist item passes.
- **Plan → Review → Ship, one command** — `@auto` goes from vague idea to merged code.
- **Skill supply chain security** — 8-category threat scan on every skill install. Based on [Snyk's ToxicSkills research](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/).
- **Zero config, full power** — Works out of the box.

---

## The Innovation: 3-Layer Determinism

```
┌─────────────────────────────────────────────────────┐
│  L1: Commands — 15 workflows, 100% deterministic     │
│  @plan @auto @execute @review @evaluate @debug ...   │
│  Each hardcodes the full step chain. No shortcuts.   │
├─────────────────────────────────────────────────────┤
│  L2: Gates — 11 hooks, hard block (exit 2 = denied)  │
│  Agent CANNOT bypass. Secrets blocked. rm -rf blocked.│
│  Writes outside workspace blocked. No exceptions.    │
├─────────────────────────────────────────────────────┤
│  L3: Feedback — 8 hooks, advisory enrichment         │
│  Auto-lint on save. Correction detection. Semantic   │
│  knowledge injection on every prompt.                │
└─────────────────────────────────────────────────────┘
```

**Why 3 layers, not just "add more hooks"?**

Not everything should be a hard block. Blocking `rm -rf` is obvious (L2). But "you should run tests" is better as auto-triggered feedback (L3) — the agent sees test results and self-corrects. And "follow this 5-step workflow" is best as a deterministic command (L1) — the agent doesn't interpret, it executes.

The layers map to **certainty levels**: L1 = 100% (user-triggered workflow), L2 = 100% (hard block), L3 = ~50% (advisory, agent may ignore but usually doesn't because the feedback is useful).

**L1 is deterministic.** When you say `@plan`, the agent follows: deep understanding → write plan with TDD checklist → dispatch parallel reviewers → fix until APPROVE → execute via Ralph Loop. It cannot skip steps.

**L2 is a hard wall.** `exit 2` from any gate hook = operation blocked. The agent sees the block, gets a suggested alternative, and retries safely. No amount of prompt engineering bypasses this.

**L3 is compound interest.** Every correction you make is detected, persisted to `episodes.md`, and auto-injected into future sessions by keyword match. After 3 similar corrections, it promotes to a permanent rule.

---

## The Innovation: Ralph Loop

Your agent crashes mid-task? Context window fills up? No problem.

```
Ralph Loop (Python outer loop)
  │
  ├─ Spawn fresh Kiro CLI instance
  │    └─ Agent reads plan, works on next unchecked item
  │    └─ Marks item [x] when verify command passes
  │    └─ Agent exits (crash, context full, or done)
  │
  ├─ Re-verify: run all inline verify commands
  │    └─ Revert any [x] items whose verify fails
  │
  ├─ Progress check
  │    └─ Items completed? → spawn next iteration
  │    └─ 3 stalls? → circuit breaker, stop
  │
  └─ All items [x]? → ✅ Done. Print summary.
```

Each iteration gets **clean context**. No stale state accumulation. The bash loop is the reliability layer — agent intelligence is the execution layer.

---

## Commands

Commands come in two flavors:
- **MCP Prompt** (`@o/plan "build a REST API"`) — accepts natural language input inline. The agent receives your description as context.
- **Command-only** (`@execute`, `@cpu`) — triggered by keyword, no inline arguments. Reads state from files (active plan, git diff, etc.)

### 🚀 The Autonomy Spectrum

#### `@auto` "build a user auth system" _(MCP prompt)_
**Full autopilot.** One command → understand requirements → write plan with TDD checklist → dispatch parallel reviewers → auto-fix until APPROVE → Ralph Loop execution → done.

_What makes it special:_ Readiness Check — a 4-dimension checklist (Goal / Constraints / Success Criteria / Context) that validates understanding before any code is written. If anything is unclear, it asks exactly ONE question with Socratic challenge modes.

#### `@plan` "migrate from PostgreSQL to DynamoDB" _(MCP prompt)_
**Controlled execution.** Same pipeline as `@auto`, but pauses for your confirmation after Phase 0 (deep understanding) and after review. You stay in the loop.

_What makes it special:_ Every checklist item requires an inline verify command (`- [ ] API returns 200 | \`curl -sf localhost:8000/health\``). Ralph Loop re-runs these commands and reverts any `[x]` that fails. No false completions.

#### `@execute` _(command-only)_
**Resume and finish.** Loads an approved plan, launches Ralph Loop. Agent crashes don't matter — the bash loop keeps spawning fresh instances until every checklist item passes.

_What makes it special:_ Work Dir isolation — if the plan declares `**Work Dir:** worktrees/omk-foo`, execution is sandboxed there. The gate hook blocks writes outside that directory.

#### `@do` "add a health check endpoint" _(MCP prompt)_
**Quick task (< 1 hour).** No plan file, no review dispatch. Scratchpad → implement → verify → commit. For when `@plan` is overkill.

---

### 🔍 Analysis Commands

#### `@review` _(MCP prompt)_
Dispatches a reviewer subagent with the full git diff. Multi-angle review (correctness, security, performance). Every finding has P0-P3 severity and file:line citation. Auto-detects worktree context from `.active-submodule`.

#### `@evaluate` "scripts/ralph_loop.py look for simplifications" _(MCP prompt)_
**Independent code quality assessment.** 4 parallel evaluator subagents — each with a distinct persona (Refactoring Expert, Product Manager, Breaker, CSO) — assess code across 6 dimensions: Simplicity, Alignment, Correctness, Security, Robustness, Maintainability. Mandatory fill-table format prevents walk-through reviews. Also runs automatically after `@execute` completes (GAN-inspired adversarial loop, up to 3 rounds).

#### `@debug` "tests fail with timeout on CI" _(MCP prompt)_
**Systematic debugging pipeline.** Not guess-and-check — structured root cause analysis:

1. Session resume — checks `docs/investigations/` for prior work on this bug (cross-session continuity)
2. Triage — reads `episodes.md` for known patterns, builds architectural context via LSP
3. Hypothesis tree — generates ranked hypotheses, tests each with evidence
4. Fix — only after root cause is confirmed

_What makes it special:_ Investigation documents persist across sessions. If you hit a bug on Monday and resume Wednesday, the agent picks up exactly where it left off.

#### `@research` "how does Kafka handle rebalancing" _(MCP prompt)_
**3-level research:** L0 built-in knowledge → L1 web search → L2 deep dive with source cross-verification. Findings auto-persisted to file.

---

### 🔧 Git & PR Commands

#### `@fixpr` _(command-only)_
**Automated PR fixer.** Fetches ALL unresolved review threads via GraphQL, triages each comment (fix / pushback / clarify), implements fixes, replies + resolves every thread. Goal: zero unresolved threads.

_What makes it special:_ PR Blueprint — reads the full diff first to understand intent, then fixes individual comments without drifting from the PR's purpose. Protected Code list prevents reviewers from requesting changes to intentional design decisions.

#### `@cpr` _(MCP prompt)_ · `@cpu` _(command-only)_
`@cpr`: Commit → push → create PR → worktree cleanup. `@cpu`: Commit → push → merge directly.

#### `@ck` "feature/auth" _(MCP prompt)_ · `@wt` _(command-only)_
`@ck`: Checkout branch into submodule worktree with fuzzy search. `@wt`: List all worktrees, clean up merged branches.

---

### 🧠 Knowledge Commands

#### `@dream` _(command-only)_
**Automated knowledge hygiene.** Scans the entire knowledge base for rot:
- Deterministic (bash): dead links, stale episodes, orphan files, TODO markers, content staleness by type
- Semantic (LLM): content redundancy, contradictions across files, consolidation recommendations

#### `@agent` _(MCP prompt)_ · `@know` _(MCP prompt)_
`@agent`: Distill a principle into `rules.md`. `@know`: Capture a knowledge insight into `episodes.md`.

#### `@lint` _(command-only)_ · `@skill` _(command-only)_
`@lint`: Framework health check. `@skill`: List skills, match user need to closest one.

---

## The Innovation: Self-Evolving Knowledge System

This is not "save notes to a file." It's a **closed-loop intelligence pipeline** that automatically detects mistakes, extracts patterns, and rewires the agent's behavior — permanently.

### How It Works

```
You say "别用 sed 改 JSON，用 jq"
  │
  ├─ correction-detect.sh fires (中英文 30+ 纠正模式匹配)
  │
  ├─ auto-capture.sh pipeline:
  │    ├─ Gate 1: 过滤低价值 (问句丢弃, 无动作丢弃)
  │    ├─ Gate 2: 提取关键词 (英文技术术语优先, 中文动作词 fallback)
  │    ├─ Gate 3: 去重 (已在 rules.md → 跳过)
  │    └─ 写入 episodes.md: "2026-03-30 | active | sed,json,jq | 别用 sed 改 JSON"
  │
  ├─ distill.sh (background):
  │    └─ 同一关键词出现 ≥3 次 → 自动提升为 rules.md 永久规则
  │    └─ 标记源 episodes 为 "promoted"，下次 session-init 清理
  │
  └─ context-enrichment.sh (every prompt):
       └─ 用户消息包含 "sed" 或 "json" → 自动注入对应规则
       └─ 🔴 CRITICAL 规则: 每条消息都注入
       └─ 🟡 RELEVANT 规则: 关键词匹配时注入
```

### What Makes This Different

**Not just memory — it's immune system.** The agent doesn't just "remember" your correction. It builds antibodies:

1. **Real-time detection** — `correction-detect.sh` matches 30+ correction patterns in both Chinese and English ("你错了", "不是这样", "wrong approach", "try again"). No manual tagging needed.

2. **Quality gates** — Not every correction is worth persisting. `auto-capture.sh` filters out questions, vague complaints, and duplicates. Only actionable corrections with extractable keywords survive.

3. **Auto-promotion** — When the same keyword pattern appears in 3+ episodes, `distill.sh` automatically promotes it to a permanent rule with severity level (🔴 CRITICAL = always injected, 🟡 RELEVANT = keyword-matched).

4. **Smart injection** — `context-enrichment.sh` runs on every user prompt. It keyword-matches the message against `rules.md` sections and injects only relevant rules. Not the whole file — just what matters for this specific message. Budget: max 3 rules per message.

5. **Cross-session continuity** — `session-init.sh` cleans up promoted episodes, reminds about promotion candidates, and bootstraps the knowledge state. Day 1 and Day 100 use the same pipeline.

6. **Semantic search (optional)** — With OpenViking configured, `context-enrichment.sh` also queries a semantic index of all knowledge files, injecting relevant snippets even when keyword matching misses.

### Real Example from Production

After 3 corrections about macOS compatibility, the system auto-promoted this rule:

> 🔴 macOS 没有 `timeout` 命令 (GNU coreutils). Plan 里写 `timeout 60s` 在 macOS 上会 command not found. 替代: `gtimeout` (brew install coreutils). 所有跨平台 bash 脚本不能假设 timeout 存在.

Now every time the agent writes a bash script, this rule is injected. The mistake never happens again.

### Knowledge Hygiene: `@dream`

Knowledge rots. Old corrections become irrelevant. Files contradict each other. `@dream` is the automated janitor:

- **Deterministic (bash):** dead links, stale episodes (>14d → auto-resolved), orphan files, TODO markers, content staleness by type
- **Semantic (LLM):** content redundancy across files, data contradictions (e.g., "GitHub Stars 8.5K" in one file vs "10K+" in another), consolidation recommendations with priority

---

## Security

### Hook-Level Enforcement

| What's Blocked | How |
|---------------|-----|
| `rm -rf`, `sudo`, `curl\|bash` | `security/block-dangerous.sh` — hard block |
| API keys, private keys in commits | `security/block-secrets.sh` — pre-push scan |
| `sed`/`awk` on JSON files | `security/block-sed-json.sh` — use jq instead |
| File writes outside workspace | `security/block-outside-workspace.sh` |
| Source edits without active plan | `gate/enforce-ralph-loop.sh` |
| Writes outside declared Work Dir | `gate/enforce-work-dir.sh` |

### Skill Supply Chain

Every skill install goes through `audit-skill.sh` — an 8-category threat scan:

| Threat | Severity |
|--------|----------|
| Prompt injection, base64 obfuscation, jailbreaks | 🔴 CRITICAL |
| eval/exec, shell=True, backdoors | 🔴 CRITICAL |
| curl\|bash, password-protected archives | 🔴 CRITICAL |
| Reading ~/.aws/credentials, echoing API keys | 🟠 HIGH |
| Hardcoded secrets (AWS keys, GitHub tokens) | 🟠 HIGH |
| External HTTP fetches, dynamic imports | 🟡 MEDIUM |
| sudo, systemctl modifications | 🟡 MEDIUM |

CRITICAL = blocked. HIGH = warned. All installs gated — no bare `npx skills add` allowed.

---

## Full Kiro Platform Integration

OMK is built to exploit every Kiro platform capability. Not just hooks — the full stack.

### Steering Rules (`.kiro/rules/`)

Kiro's steering rules are always-on instructions injected into every agent interaction. OMK uses 4 steering files as the "constitution":

| File | What It Steers |
|------|---------------|
| `enforcement.md` | Complete hook registry with event types, determinism layers (L0-L3), config generation rules |
| `code-analysis.md` | **LSP-first mandate** — agent must use `search_symbols`, `find_references`, `get_diagnostics` before grep. AST pattern search before text search. `pattern_rewrite` before sed. |
| `commands.md` | Command routing table: which `@command` triggers which workflow |
| `reference.md` | Project conventions, naming patterns, file organization rules |

_Why this matters:_ Steering rules are injected by the platform, not by the agent. The agent cannot choose to ignore them. This is a harder guarantee than AGENTS.md instructions.

### LSP-First Code Intelligence

Most AI agents read code with `grep` and `cat`. OMK agents use **Language Server Protocol** — the same intelligence that powers your IDE:

```
# Instead of: grep -rn "handleRequest" src/
# OMK agent does:
search_symbols("handleRequest")     → find definition
find_references(file, line, col)    → find all callers
get_hover(file, line, col)          → get type signature
get_diagnostics(file)               → get compiler errors
pattern_search("try { $$$ } catch") → find all error handlers (AST-level)
```

Configured via `.kiro/settings/lsp.json` with support for Rust, Python, TypeScript, Go, and more. The `code-analysis.md` steering rule enforces this — the agent is steered away from grep for code navigation.

### Skills, Hooks, Tools — Single Source of Truth

```
hooks/     ─── symlinked ──→  .kiro/hooks
skills/    ─── symlinked ──→  .kiro/skills
commands/  ─── symlinked ──→  .kiro/prompts
```

You edit in `hooks/`, `skills/`, `commands/`. The `.kiro/` directory is generated. `scripts/generate_configs.py` produces agent configs, settings, and wiring from these sources. Never edit `.kiro/` directly.

| Kiro Feature | OMK Usage |
|-------------|-----------|
| **Hooks** (PreToolUse/PostToolUse/Stop) | 19 hooks: security gates, workflow enforcement, auto-lint, correction detection, knowledge injection |
| **Skills** (on-demand capabilities) | 14 skills: planning, reviewing, coding, debugging, research, self-reflect, etc. |
| **Prompts** (MCP commands) | 10 MCP prompts accepting natural language: `@o/plan "build X"`, `@o/debug "Y fails"` |
| **Agents** (subagent configs) | 5 agent profiles: pilot, reviewer, researcher, executor, default |
| **Steering** (always-on rules) | 4 rule files: enforcement, code-analysis, commands, reference |
| **Settings** (LSP + MCP) | LSP for 5+ languages, MCP server for prompt registration |

---

```
oh-my-kiro/
├── commands/        # 14 custom commands (single source of truth)
├── hooks/
│   ├── security/    # 4 hard blocks
│   ├── gate/        # 7 enforcement gates
│   ├── feedback/    # 8 advisory hooks
│   └── _lib/        # Shared: patterns, distill, OV client
├── skills/          # 14 on-demand capabilities
├── scripts/
│   ├── ralph_loop.py        # The execution engine
│   ├── generate_configs.py  # Single source → platform configs
│   └── mcp-prompts.py       # MCP prompt server
├── knowledge/       # Persistent memory (rules, episodes, INDEX)
├── agents/          # Subagent prompts (reviewer, researcher)
├── tools/           # CLI: init, sync, audit, validate
└── tests/           # 56 test files
```

**Key design:** `hooks/`, `skills/`, `commands/` are the single source of truth. Platform configs (`.kiro/`) are generated by `generate_configs.py`. Never edit generated files.

---

## Cherry-Pick What You Need

| Want | Copy |
|------|------|
| Just the execution engine | `scripts/ralph_loop.py` + `scripts/lib/` |
| Just self-learning | `skills/omk-self-reflect/` + `knowledge/rules.md` + `knowledge/episodes.md` |
| Just security hooks | `hooks/security/` + `hooks/_lib/patterns.sh` |
| Just skill auditing | `tools/audit-skill.sh` + `tools/install-skill.sh` |

---

## Extending

See [EXTENSION-GUIDE.md](docs/EXTENSION-GUIDE.md) for adding project-specific skills, hooks, and knowledge.

---

## Design Principles

1. **Deterministic over hopeful** — Commands and hard blocks, not soft prompts
2. **Compound over time** — Every session makes the next one better
3. **Code over prose** — Hooks enforce, words suggest
4. **Evidence before claims** — Verification first, always
5. **Secure by default** — All skill installs audited, dangerous commands blocked
6. **Bold reform over timid patches** — Quality over backward compatibility

---

## License

MIT
