Lightweight command for small tasks (< 1 hour). No plan file, no review dispatch. Prevents context drift across multi-turn interactions.

## Stage 1: Scratchpad (MANDATORY, even if task seems trivial)

Before ANY code change, write a scratchpad to `/tmp/task-scratch.md`:

```markdown
## Task: <one-line description>
- Files: <list files to read/modify, discovered via LSP>
- Constraint: <key constraints or gotchas>
- Verify: <how to verify success>
```

Discovery steps (silent, no user output):
1. `search_symbols` / `find_references` / `get_diagnostics` to identify all affected files
2. Read each affected file's relevant sections (NOT entire files — use line offsets)
3. Update scratchpad with actual file list and key findings

## Stage 2: Execute

Make changes following `skills/omk-coding/SKILL.md` Phase 1-4.

**Context anchor rule**: After EVERY code modification, append a one-line status to the scratchpad:
```
- [done] modified hooks/feedback/context-enrichment.sh L37-41: expanded CN keywords
- [done] created symlink commands/auto.md → oh-my-kiro
- [blocked] test fails: grep pattern doesn't match "超时"
```

## Stage 3: Verify

1. Run the verify method from scratchpad
2. Re-read scratchpad to confirm all items addressed
3. Report result to user

## Multi-turn recovery

If the conversation has gone ≥ 3 turns on this task:
1. STOP and re-read `/tmp/task-scratch.md`
2. Compare current state vs scratchpad — identify drift
3. If drifted, state what drifted and correct course

---
User's task:
