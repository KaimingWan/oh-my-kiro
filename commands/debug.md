You MUST follow this exact sequence. @debug is a fully automated debugging pipeline — no user confirmation between stages. The goal is systematic root cause analysis, not guess-and-check.

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

## Stage 0: Session Resume Check

Before starting any investigation, check for existing investigation documents:

1. List `docs/investigations/` — look for files matching the current bug topic
2. If a matching document exists:
   - Read its **Status Overview** section to understand current state
   - Read its **Ruled Out** section to avoid re-investigating dead ends
   - Read its **Decision Log** to understand prior decisions
   - Resume from the last recorded state — do NOT restart from scratch
3. If no matching document exists:
   - Create `docs/investigations/{date}-{topic}.md` using `skills/omk-debugging/investigation-template.md` as template
   - Fill in the Problem Statement with the user's bug report

**Session Resume Protocol:** Every new session MUST check `docs/investigations/` first. The investigation document is the single source of truth for cross-session continuity.

## Stage 1: Triage & Context

1. Read `knowledge/episodes.md` — check if this bug pattern has occurred before
2. Build Architectural Context around the bug:
   - `generate_codebase_overview` → module structure
   - `find_references` on bug's core symbol(s) → all callers
   - `get_document_symbols` on bug's file(s) → internal structure
3. Classify failure type:

| Category | Signal |
|----------|--------|
| Logic/Semantic | Test fails, wrong output |
| Environment/Config | Works locally, fails elsewhere |
| Concurrency/Timing | Intermittent |
| Invalid Invocation | Schema error, 400 response |
| Under-specified Intent | Need more context |

4. Write triage summary to the investigation document (`docs/investigations/{date}-{topic}.md`):
   - Fill in **Problem Statement**
   - Add initial entries to **Evidence Table** (L0 facts from diagnostics)
   - Build initial **Investigation Tree** with top-level branches
   - Update **Status Overview** with triage results and next steps

## Stage 2: Root Cause Investigation

Follow `skills/omk-debugging/SKILL.md` Phase 1 + `references/root-cause-protocol.md`.

Tool sequence — use LSP tools, NOT grep:

| Step | Action |
|------|--------|
| 1 | `get_diagnostics` on failing file(s) |
| 2 | `search_symbols` → `goto_definition` → `find_references` on involved symbols |
| 3 | Read error messages / stack traces completely |
| 4 | Reproduce the bug consistently |
| 5 | Check recent changes (`git diff`, recent commits) |

Produce **Diagnostic Evidence** before proceeding:
```
Diagnostic Evidence:
- failure_type: [category]
- get_diagnostics: [errors found]
- search_symbols: [symbols located]
- find_references: [callers/usage sites]
- key_variables:
  - var_name / expected / actual / location
- Root cause hypothesis: [conclusion]
```

**Gate:** Without Diagnostic Evidence, DO NOT proceed to Stage 3.

**完成后:** Update investigation document — add L0 diagnostic evidence to Evidence Table, update Status Overview with findings and next steps.

## Stage 3: Pattern Analysis & Hypothesis

Follow `skills/omk-debugging/SKILL.md` Phase 2-3 + `references/pattern-analysis.md`.

1. Find working examples of similar code in the codebase
2. Compare working vs broken — list ALL differences
3. Form ONE hypothesis: "X is the root cause because Y"
4. Test with the SMALLEST possible change — one variable at a time
5. If hypothesis fails → form NEW hypothesis, don't stack fixes

Append to scratch:
```
- Hypothesis: <statement>
- Test: <what minimal change was tried>
- Result: confirmed | rejected → <next hypothesis if rejected>
```

**Gate:** Hypothesis must be confirmed before proceeding to Stage 4.

**完成后:** Update investigation document — record hypothesis and test results in Decision Log, add experiments to Experiment Log, update Status Overview.

## Stage 4: Fix & Verify

Follow `skills/omk-debugging/SKILL.md` Phase 4 + `references/implementation-fix.md`.

1. `get_diagnostics` → record baseline
2. Create failing test case (if possible)
3. Implement SINGLE fix addressing root cause — no bundled changes
4. `get_diagnostics` → zero new diagnostics, or revert
5. Run tests → verify fix, no regressions
6. Self-explain: root cause → fix logic → side effects (check against Architectural Context)

**3-Strike Rule:** If 3 fix attempts fail → STOP, question the architecture, discuss with user.

**完成后:** Update investigation document — update Status Overview to final state (🟢 Resolved or 🟡 Partial), record final decision in Decision Log.

## Stage 5: Report

Generate the final report from the investigation document (`docs/investigations/{date}-{topic}.md`):

```markdown
## Debug Report
- **Bug:** <description>
- **Root Cause:** <what was actually wrong>
- **Fix:** <what was changed and why>
- **Verification:** <test results>
- **Side Effects:** <none | list>
```

If bug is a new pattern, append one-line summary to `knowledge/episodes.md`.

## Red Flags — Auto-Rollback to Stage 2

If at ANY stage you catch yourself:
- Proposing fixes without Diagnostic Evidence
- Using grep instead of LSP tools for code navigation
- Saying "just try X"
- Stacking multiple changes at once
- Skipping reproduction

→ **STOP. Return to Stage 2.** Load `references/red-flags.md` for full list.

---
User's bug report:
{content}
