---
name: omk-skill-creation
description: "Create high-quality, production-ready skills from scratch. Trigger when user says 'create skill', 'new skill', 'write a skill', 'make a skill', '创建 skill', '写个 skill', 'skillify', or when packaging a repeated workflow into a reusable skill. Also trigger when reviewing or improving existing skills."
---

# Skill Creation — From Idea to Production

## Trigger Examples
- "把这个重复流程做成 skill"
- "create a new skill for code review"
- "帮我写一个 SEO 研究的 skill"
- "review and improve this skill"
- "这个工作流应该 skillify"

## Philosophy

> Context window is a public good. Only add what the agent doesn't already know.

A skill is an onboarding manual for the agent — after reading it, the agent knows your process, standards, and preferences without re-teaching every session.

## Phase 0: Should This Be a Skill?

Before writing anything, decide the right mechanism:

| Signal | Mechanism |
|--------|-----------|
| Rule needed in EVERY conversation | AGENTS.md / rules.md |
| Must run automatically on events | Hook (gate/ or feedback/) |
| Teaches agent a specific workflow | **Skill** ← you are here |
| Gives agent a new tool/API | MCP server |
| Needs isolated context execution | Subagent |

**Skill ROI threshold**: Will this workflow run ≥3 times? If not, just explain in conversation.

## Phase 1: Design (Before Writing SKILL.md)

### Step 1: Define Use Cases

Write 3-5 concrete user prompts that should trigger this skill. Not abstract descriptions — actual sentences users will type:

```
Example for a "daily planning" skill:
- "plan my day"
- "start work"
- "今天做什么？"
- "morning routine"
- "daily standup prep"
```

These prompts shape everything: skill name, description, input/output, workflow steps.

### Step 2: Define Input → Output

| Question | Answer |
|----------|--------|
| What does the user provide? | (file, URL, text, nothing?) |
| What does the skill produce? | (file, report, action, decision?) |
| What format? | (markdown, JSON, email, code?) |

### Step 3: Choose Pattern

| Need external APIs/real-time data? | → Pattern C: Skill + MCP |
|-------------------------------------|--------------------------|
| Need deterministic computation? | → Pattern B: Prompt + Scripts |
| Agent judgment alone is enough? | → Pattern A: Prompt-Only |

**When in doubt, start with Pattern A.** Add scripts later if needed.

### Step 4: Choose Freedom Level

| Fragility | Freedom | Example |
|-----------|---------|---------|
| High (DB migration, deploy) | Low — exact commands, no variation | `Run exactly: python migrate.py --verify` |
| Medium (code generation) | Medium — template with parameters | Pseudocode + config options |
| Low (code review, writing) | High — guidelines + heuristics | "Check for X, Y, Z" |

## Phase 2: Write SKILL.md

### File Structure

```
my-skill/
├── SKILL.md              # Required. < 500 lines
├── scripts/              # Optional. Deterministic code
├── references/           # Optional. Loaded on demand
└── assets/               # Optional. Templates, data
```

### Frontmatter (Critical)

The description determines whether the skill ever triggers. Agent defaults to NOT triggering — your description must be "pushy."

```yaml
---
name: kebab-case-name        # ≤64 chars, lowercase + hyphens only
description: >                # ≤1024 chars, third person
  [What it does]. Trigger when user says [keyword1], [keyword2],
  [keyword3], or [scenario description]. Also trigger when
  [implicit trigger condition].
---
```

**Rules:**
- Third person always ("Processes X", not "I help you" or "You can use this")
- First sentence: what it does (purpose)
- Second sentence: explicit trigger keywords (list actual user phrases)
- Third sentence: implicit triggers (file types, contexts, patterns)
- Be specific > be brief. Use all 1024 chars if needed

**Bad**: `description: Helps with data tasks`
**Good**: `description: Analyze sales/revenue CSV files to find patterns and calculate metrics. Trigger when user mentions sales data, revenue analysis, profit margins, or uploads xlsx/csv with financial column headers.`

### Body Structure

```markdown
## Trigger Examples
- "realistic user prompt 1"
- "realistic user prompt 2" (different language/style)
- "realistic user prompt 3"
- "realistic user prompt 4"
- "realistic user prompt 5"

## [Workflow Steps]
Step 1: ...
Step 2: ...

## [Rules / Constraints]

## [Output Format] (if applicable)
```

### Writing Principles

1. **Concise is key** — Claude is smart. Only add what it doesn't know. Challenge every paragraph: "Does this justify its token cost?"
2. **Reasons > commands** — "Show command before executing, because users need to verify safety" beats "ALWAYS show commands. NEVER execute directly."
3. **Examples > explanations** — One input/output pair teaches more than three paragraphs of description
4. **One default, one escape hatch** — Don't list 5 options. Pick the best one, mention the alternative for edge cases
5. **Consistent terminology** — Pick one term, use it everywhere. Not "endpoint/URL/route/path" interchangeably

### Progressive Disclosure

- SKILL.md = overview + navigation (< 500 lines)
- `references/` = detailed docs, loaded on demand
- `scripts/` = executable code, runs without entering context
- Reference depth: max 1 level. SKILL.md → reference.md. Never reference.md → sub-reference.md
- For references > 100 lines, add a table of contents at top

## Phase 3: Test

### Write Messy Test Prompts

Real users make typos, use slang, forget file names. Test with realistic prompts, not clean ones:

```
# Good (realistic)
"ok so my boss sent me this xlsx (its in downloads, called
something like 'Q4 sales final FINAL v2.xlsx') and she wants
profit margin as a percentage"

# Bad (too clean)
"Please analyze the sales data in the uploaded Excel file
and add a profit margin column"
```

### Iteration Loop

1. Run skill with test prompts
2. Did it trigger? If not → fix description
3. Did it produce correct output? If not → fix workflow steps
4. Is output format right? If not → fix template/examples
5. Repeat

### Check Trigger Rate

Short simple requests rarely trigger skills. Ensure test set includes prompts with enough complexity and matching keywords.

## Phase 4: Review Checklist

Before shipping, verify:

- [ ] Description is specific, includes trigger keywords, third person
- [ ] SKILL.md body < 500 lines
- [ ] Has 5 Trigger Examples with realistic prompts
- [ ] Long content split into references/
- [ ] No time-sensitive info (or in "old patterns" section)
- [ ] Consistent terminology throughout
- [ ] Concrete examples, not abstract explanations
- [ ] Reasons given for rules (not just MUST/NEVER)
- [ ] Scripts handle errors explicitly (don't punt to agent)
- [ ] No hardcoded secrets or magic numbers
- [ ] Tested with messy realistic prompts

## Anti-Patterns

| Don't | Do Instead |
|-------|-----------|
| Stuff everything in SKILL.md | Split to references/ at 500 lines |
| Vague description ("helps with data") | Specific + trigger keywords |
| First/second person description | Third person always |
| List 5 equivalent options | One default + one escape hatch |
| MUST/NEVER without reason | Explain why the rule exists |
| Test with clean prompts only | Test with messy realistic prompts |
| Write skill before iterating in conversation | Get workflow right first, then extract |
| Deeply nested references (A→B→C) | Max 1 level deep |
| Assume packages installed | List dependencies explicitly |
| Magic numbers in scripts | Document why each value was chosen |

## OMK-Specific Conventions

When creating skills for oh-my-kiro projects:

1. **Naming**: `omk-` prefix for framework skills, project-specific names for project skills
2. **Location**: Framework skills → `oh-my-kiro/skills/`, project skills → `skills/`
3. **Security**: Run `bash tools/audit-skill.sh <dir>` before installing external skills
4. **Sync**: After creating in submodule, run `bash tools/sync-omk.sh .` to propagate
5. **Registration**: `python3 scripts/generate_configs.py` to update platform configs
