Before dispatching the reviewer, determine the correct working directory:

## Step 1: Resolve review target

1. If the user specifies a path after @review (e.g., `@review worktrees/omk-foo`), use that path.
2. Otherwise, check if `.active-submodule` exists in the project root:
```bash
if [ -f .active-submodule ]; then
  jq -r '.worktree // empty' .active-submodule
fi
```
3. If a worktree path is found, use it as the review working directory.
4. If neither is available, review the project root (default behavior).

Set the resolved path as `REVIEW_DIR`.

## Step 2: Gather diff context

Run in the resolved directory to build the review query:
```bash
cd "$REVIEW_DIR"
git diff --stat
git diff
```

If the diff is empty (no unstaged changes), also check staged changes:
```bash
cd "$REVIEW_DIR"
git diff --cached --stat
git diff --cached
```

## Step 3: Dispatch reviewer

Dispatch a reviewer subagent (`agent_name: "reviewer"`) with this query:

"Review the code changes in `<REVIEW_DIR>`. Run `git -C <REVIEW_DIR> diff --stat` then `git -C <REVIEW_DIR> diff`. If no unstaged changes, check `git -C <REVIEW_DIR> diff --cached`. Categorize findings: P0 Critical / P1 High / P2 Medium / P3 Low. Check: correctness, security, SOLID violations, test coverage, edge cases. Be specific — cite file:line and show code examples."

Report the findings to me.
