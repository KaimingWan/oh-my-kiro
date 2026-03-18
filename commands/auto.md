You MUST follow this exact sequence. @auto is a fully automated pipeline — no user confirmation between stages except during Expansion questions.

## Stage 1: Expansion (Phase 0 + Readiness Check)

Follow `skills/omk-planning/SKILL.md` Phase 0 including **Step 6: Readiness Check**.

- Run the 4-dimension checklist (Goal / Constraints / Success Criteria / Context)
- If any dimension is ❌, ask the user ONE question (with Challenge Modes on 2nd+ question)
- Once all dimensions are ✅, generate a one-paragraph spec summarizing the validated understanding
- `touch .brainstorm-confirmed`

Difference from @plan: @plan waits for explicit user confirmation after Phase 0. @auto proceeds automatically once Readiness Check passes.

## Stage 2: Planning (Phase 1)

Read `skills/omk-planning/SKILL.md` Phase 1. Write plan to `docs/plans/<date>-<slug>.md` with Goal, Tasks (TDD structure), `## Review`, and `## Checklist` with verify commands.

Follow all Checklist Structure Rules from `commands/plan.md` Step 2.

## Stage 3: Review (Phase 1.5 + Pre-mortem)

Follow `skills/omk-planning/SKILL.md` Phase 1.5:
1. Run **Pre-mortem Analysis** — identify 3 failure risks (Integration / Assumption / Environment)
2. Select review angles (2 fixed + 2 random = 4 reviewers)
3. Dispatch 4 reviewer subagents in parallel with pre-mortem questions injected

**Handling REQUEST CHANGES:**
- @auto autonomously revises the plan based on reviewer feedback (max 2 revision rounds)
- After each revision, re-dispatch reviewers for the changed sections
- If still REQUEST CHANGES after 2 rounds: **STOP** and tell the user what remains unresolved. User must intervene manually.

## Stage 4: Execution

After all reviewers APPROVE (or after user resolves remaining issues):
1. Write plan path to `docs/plans/.active`
2. `unlink .brainstorm-confirmed 2>/dev/null || true`
3. Auto-commit plan artifacts (explicit file paths only, never `git add -A`)
4. Run `@execute` to launch task execution

## Stage 5: Completion

When execution finishes:
- Report final status (completed / remaining / skipped items)
- If items remain, summarize what failed and suggest next steps
- Clean up `.active` if all items completed

---
User's requirement:
(The user's next message is the requirement. If this is the first message after @auto was invoked and no requirement appears above, wait for the user's next message — it will contain the requirement. Do NOT ask "what do you want to do?" — the user already knows they need to provide input after @auto.)
