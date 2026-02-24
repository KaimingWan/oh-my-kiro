# OMCC Extension Guide

Quick reference for extending OMCC in downstream projects.

## Add a Skill

1. Create `skills/my-skill/SKILL.md` with frontmatter and instructions
2. Register in `.omcc-overlay.json`:
   ```json
   { "extra_skills": ["skills/my-skill"], "extra_hooks": {} }
   ```
3. Validate: `bash tools/validate-project.sh`
4. Generate configs: `python3 scripts/generate_configs.py --overlay .omcc-overlay.json`

## Add a Hook

1. Create `hooks/project/my-hook.sh` (must be executable)
2. Register in `.omcc-overlay.json`:
   ```json
   { "extra_hooks": { "postToolUse": [{"command": "hooks/project/my-hook.sh"}] } }
   ```
3. Valid events (camelCase): `agentSpawn`, `userPromptSubmit`, `preToolUse`, `postToolUse`, `stop`
4. Validate: `bash tools/validate-project.sh`

## Install a Community Skill

```bash
bash tools/install-skill.sh <SKILL_PATH>
```

This copies the skill, registers it in `.omcc-overlay.json`, and regenerates configs.

## Validate Your Project

```bash
bash tools/validate-project.sh [PROJECT_ROOT]
```

Exits 1 on errors (broken paths, invalid JSON, missing markers).
Exits 0 with warnings (missing frontmatter, large files).

## Sync OMCC Updates

```bash
bash tools/sync-omcc.sh
```

Updates the OMCC submodule, validates, and regenerates all agent configs.

## Don'ts

- Do **not** edit files inside `.omcc/` — they are regenerated on sync
- Do **not** duplicate framework skills — add project-specific skills only
- Do **not** name project hooks the same as framework hooks
- Do **not** add project rules to `CLAUDE.md` — use `AGENTS.md` project sections
- Do **not** skip validation — it is a hard gate before config generation
