# Evaluator Plan Findings

## Codebase Patterns

- **Command file pattern:** Commands in `commands/` are markdown files with Step 1/2/3 structure. See `commands/review.md` for reference pattern (resolve target → gather context → dispatch subagent → report).
- **Skills directory naming:** Skills use `omk-` prefix (e.g., `skills/omk-debugging/`), not bare names.
- **Subagent dispatch:** Use `use_subagent` with up to 4 parallel entries. Each gets a persona, specific instructions, and structured output requirements.
- **Hook enforcement:** Checklist marking hook requires the exact verify command to be run via `execute_bash` (not wrapped in echo) immediately before the `str_replace` call.

## Design Decisions

- Evaluator prompt uses 7 REJECTED enforcement points (4 per-subagent empty-table rules + 3 in aggregation) to prevent rubber-stamp evaluations.
- Canary questions are per-subagent and require reading actual source code to answer — prevents evaluators from generating generic feedback without reading the diff.
