# Skill Authoring Reference

> Detailed reference material for skill creation. Read on demand, not preloaded.

## Sources

This reference synthesizes best practices from:
- Anthropic official: "Skill authoring best practices" (platform.claude.com/docs)
- Anthropic official: "A complete guide to building skills for Claude" (2026-01-29)
- Anthropic official: skill-creator meta-skill (improved 2026-03)
- TDS: "How to Build a Production-Ready Claude Code Skill" by Hajime Takeda (2026-03-16)
- Community: shareuhack.com skill guide, yu-wenhao.com skill guide

## Description Writing Deep Dive

### Why Descriptions Matter So Much

At startup, only name + description (~100 tokens per skill) are loaded. The agent uses
this metadata alone to decide whether to load the full SKILL.md. If description is vague,
the skill never triggers — no matter how good the body is.

Agent behavior: defaults to NOT triggering. It would rather skip a skill than trigger
incorrectly. Testing shows vague descriptions drop auto-trigger accuracy to ~55%.

### Description Formula

```
[What it does in one sentence]. [Trigger when user says "keyword1", "keyword2",
"keyword3", or describes scenario X]. [Also trigger when implicit condition Y].
```

### Constraints
- name: ≤64 chars, lowercase + hyphens only, no "anthropic"/"claude"
- description: ≤1024 chars, non-empty, no XML tags
- Always third person ("Processes X", not "I help you")

### Trigger Keyword Strategy

1. Start from use cases — what will users actually say?
2. Include both English and Chinese keywords if bilingual
3. Include synonyms (e.g., "review" + "check" + "audit")
4. Include implicit triggers (file types, contexts)
5. More trigger phrases > fewer (agent under-triggers, not over-triggers)

## Three-Layer Loading (Progressive Disclosure)

| Layer | What | When Loaded | Token Cost |
|-------|------|-------------|------------|
| L1: Metadata | name + description | Always (startup) | ~100 tokens/skill |
| L2: SKILL.md body | Full instructions | When agent deems relevant | Variable |
| L3: references/ + scripts/ | Supporting files | On demand | Zero until read |

Context budget: skills get ~2% of context window, fallback cap 16,000 chars.
Check with `/context` command if skills are being excluded.

## Pattern Details

### Pattern A: Prompt-Only
Just SKILL.md with markdown instructions. No scripts.
Best for: brand guidelines, coding standards, review checklists, writing style.
When: Agent judgment alone is sufficient.

### Pattern B: Prompt + Scripts
SKILL.md + executable code in scripts/.
Best for: data transformation, PDF/Excel processing, template generation, numerical reports.
Scripts execute without entering context — saves tokens and ensures accuracy.
Supported: Python, JavaScript/Node.js, Bash.

### Pattern C: Skill + MCP/Subagent
Calls MCP servers or spawns subagents from within the workflow.
Best for: workflows involving external services (create issue → branch → fix → PR).
More moving parts = more debugging. Get comfortable with A/B first.

## Freedom Level Examples

### Low Freedom (fragile operations)
```markdown
## Database Migration
Run exactly this script:
```bash
python scripts/migrate.py --verify --backup
```
Do not modify the command or add additional flags.
```

### Medium Freedom (preferred pattern exists)
```markdown
## Generate Report
Use this template and customize as needed:
```python
def generate_report(data, format="markdown", include_charts=True):
    # Process data → generate output → optionally include visualizations
```
```

### High Freedom (multiple valid approaches)
```markdown
## Code Review Process
1. Analyze code structure and organization
2. Check for potential bugs or edge cases
3. Suggest improvements for readability
4. Verify adherence to project conventions
```

## Common Patterns

### Template Pattern
Provide output format templates. Strict for APIs/data, flexible for prose.

### Examples Pattern
Input/output pairs teach better than descriptions:
```
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### Conditional Workflow Pattern
```
1. Determine type:
   Creating new? → Follow "Creation workflow"
   Editing existing? → Follow "Editing workflow"
```

### Feedback Loop Pattern
Run → validate → fix → validate again. Greatly improves output quality.

### HITL (Human-in-the-Loop) Pattern
Pause after each stage, wait for user confirmation before proceeding.
Experience shows fully automated pipelines produce lower quality than
human-reviewed-at-each-stage pipelines.

### File-Based Communication Pattern
Each skill writes output to a file. Next skill reads the same file.
More reliable than passing data through context (context disappears on session end).

## Evaluation-Driven Development

1. Identify gaps: Run agent on tasks WITHOUT the skill. Document failures.
2. Create evaluations: 3+ scenarios testing those gaps.
3. Establish baseline: Measure performance without skill.
4. Write minimal instructions: Just enough to pass evaluations.
5. Iterate: Execute evaluations, compare against baseline, refine.

## Script Best Practices

- Handle errors explicitly — don't punt to agent
- Document all constants (no magic numbers)
- List required packages in SKILL.md
- Make execution intent clear: "Run X" (execute) vs "See X" (read as reference)
- Prefer scripts for deterministic operations over asking agent to generate code
- Use forward slashes in paths (even on Windows)

## Skill Lifecycle

Skills aren't write-once-and-forget:
1. v1: Get workflow right in conversation first, then extract
2. v2-v3: Fix issues discovered in daily use
3. Ongoing: Monthly review — does skill still match reality?
4. Retirement: Remove or merge rarely-used skills

> "Good workflows are grown, not designed." — Anthropic skill-creator guide
