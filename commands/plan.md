You MUST follow this exact sequence. Do NOT skip or reorder any step.

## Step 1: Deep Understanding (skill: planning Phase 0)
Follow skills/planning/SKILL.md Phase 0 to build deep understanding of the goal. Ask clarifying questions, research if needed, and present design for creative/architectural work. Do NOT proceed until the user confirms the direction. After user confirms: `touch .brainstorm-confirmed`

## Step 2: Writing Plan (skill: planning)
Read skills/planning/SKILL.md, then write a plan to docs/plans/<date>-<slug>.md. The plan MUST include: Goal, Steps with TDD structure, an empty ## Review section, and a ## Checklist section with all acceptance criteria as `- [ ]` items. The checklist is the contract — @execute will not proceed without it.

### Checklist Structure Rules (CRITICAL — Ralph Loop depends on these)
1. **Every Phase MUST have its own `- [ ]` checklist items inline** — directly after the implementation code in that Phase. Do NOT collect all checklist items into a single final Phase.
2. **Each checklist item MUST include an inline verify command** using the format: `- [ ] Description | \`verify_command\`` (e.g., `- [ ] OpenViking installed | \`ov --version\``). The verify command must return exit code 0 on success.
3. **No Phase may contain only code blocks without checklist items.** If a Phase has implementation steps, it must have corresponding `- [ ]` items that Ralph Loop can track.
4. **Checklist items must be actionable, not just observational.** Bad: `- [ ] System looks good`. Good: `- [ ] Gateway responds 200 | \`curl -sf http://127.0.0.1:8000/health\``.
5. **A final "Integration Test" Phase is allowed** but it must only contain cross-Phase verification items, not repeat items that belong to earlier Phases.

## Step 3: Verify Checklist Exists
Before dispatching reviewer, confirm the plan file contains a `## Checklist` section with at least one `- [ ]` item. If missing, add it NOW — do not proceed to review without it.

## Step 4: Plan Review (skill: planning)
Follow `skills/planning/SKILL.md` Phase 1.5 for plan review. Select review angles based on plan complexity, dispatch reviewer subagent(s), and apply calibration rules defined there.

## Step 5: Address Feedback
If reviewer verdict is REQUEST CHANGES or REJECT:
  - Fix the plan based on reviewer feedback
  - Mark old decisions as ~~deprecated~~ with reason
  - Re-dispatch reviewer for a second round
  - Repeat until APPROVE

## Step 6: User Confirmation
Show the final plan with reviewer verdict. User confirms by saying `@execute` (which also triggers execution) or just "确认"/"confirm".

## Step 7: Hand Off to Execute
After user confirms (including via `@execute`):
1. Write the plan file path to `docs/plans/.active` (e.g., `echo "docs/plans/2026-02-14-feature-x.md" > docs/plans/.active`)
2. Clean up: `unlink .brainstorm-confirmed 2>/dev/null || true`
3. **Auto-commit plan artifacts** — ralph_loop.py requires a clean working tree. Only commit files the agent created/modified during this plan session (plan file, .active, any skill/prompt changes). Do NOT `git add -A` — user may have unrelated edits in progress. Use explicit file paths:
   ```
   git add docs/plans/<plan-file>.md docs/plans/.active [other files agent touched]
   git commit -m "plan: <plan-slug> (reviewed, approved)"
   ```
   If `git status --porcelain` still shows untracked/modified files after this commit, warn the user: "You have uncommitted changes outside this plan. Stash or commit them before @execute."
4. Launch Ralph Loop:
   ```bash
   python3 scripts/ralph_loop.py
   ```
   Report results when it finishes (see commands/execute.md Step 4).

---
User's requirement:
(If no requirement provided below, ask the user what they want to plan before proceeding.)
