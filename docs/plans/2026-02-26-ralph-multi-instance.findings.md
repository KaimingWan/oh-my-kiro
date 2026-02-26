# Ralph Multi-Instance Findings

## Decision: Slug derivation from plan pointer filename

- Plan pointer `docs/plans/.active` → slug = "" (backward compatible, no suffix)
- Plan pointer `docs/plans/2026-02-26-sitebox-feat.md` → slug = `2026-02-26-sitebox-feat` (filename stem)
- This means lock/log/result files get `-{slug}` suffix: `.ralph-loop-{slug}.lock`, etc.

## Decision: instance_path uses Path.with_name

`instance_path()` injects the slug between stem and suffix using `Path.with_name()`. This correctly handles both flat paths (`.ralph-loop.lock`) and nested paths (`docs/plans/.ralph-result`).

## Decision: Hook verify commands must use bash -c for env propagation

Original plan had `VAR=x echo '...' | bash hook.sh` which doesn't propagate env vars through pipes. Fixed to `bash -c 'export VAR=x; echo ... | bash hook.sh'`.

## Decision: enforce-work-dir hook placement

Registered before `pre-write.sh` in pilot.json so boundary enforcement happens before checklist verification. The hook is a no-op when `_RALPH_LOOP_RUNNING` is unset, so zero overhead outside ralph loop.
