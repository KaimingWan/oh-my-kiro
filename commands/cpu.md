Commit all changes, push to remote, and complete branch lifecycle. (CPU = Commit Push Update-readme)

## Scope
Only operate on the current project (where AGENTS.md lives). NEVER cd into or commit/push other repositories.

## Steps

### Step 0: Update README (the "U" in CPU)

Before committing, check if README.md needs updating based on what changed.

1. Run `git diff --name-only HEAD` (or `git diff --name-only --cached HEAD` if staged) to get changed files.

2. Check each category against README.md:

| Changed path pattern | README section to check |
|---------------------|------------------------|
| `commands/*.md` (new file) | Command table (`@command` rows) |
| `skills/*/SKILL.md` (new file) | Skills table or list |
| `hooks/**/*.sh` (new file) | Hooks section or directory tree |
| Any new top-level directory | Directory tree in README |

3. For each mismatch found:
   - Read the new file to understand what it does (first line or description field)
   - Add the missing entry to the appropriate README section
   - Match the format of existing entries exactly

4. If no README updates needed, skip silently. If updates were made, stage them with the rest.

**Rule:** Only ADD entries for new files. Do NOT rewrite, reformat, or "improve" existing README content.

### Step 1: Stage & Commit
1. `git add -A && git status --short` — show what's staged
2. Ask user for commit message if not provided, or generate one from the diff
3. `git commit -m "<message>"`
4. `git push`
5. Report: commit hash + push result

### Step 2: Detect Worktree

Check if currently inside a git worktree:

```bash
wt_dir=$(git rev-parse --git-common-dir 2>/dev/null)
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [ "$wt_dir" != "$git_dir" ]; then
  echo "IN_WORKTREE=true"
  # Get the base branch (the branch of the main working tree)
  base_branch=$(git -C "$wt_dir/.." branch --show-current 2>/dev/null || echo "main")
  echo "BASE_BRANCH=$base_branch"
else
  echo "IN_WORKTREE=false"
fi
```

- If **not in worktree** → STOP here. Done (original behavior).
- If **in worktree** → continue to Step 3.

### Step 3: Check Branch Protection

```bash
# Extract owner/repo from remote
remote_url=$(git remote get-url origin)
repo_slug=$(echo "$remote_url" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
gh api "repos/${repo_slug}/branches/${base_branch}/protection" 2>&1
```

- **404 (not protected)** → Step 4A (merge locally)
- **200 (protected)** → Step 4B (create PR)
- **gh CLI error / no auth** → fall back to Step 4B (safer default)

### Step 4A: Merge to Main (unprotected)

```bash
feature_branch=$(git branch --show-current)
worktree_path=$(pwd)

# Switch to main working tree
cd "$(git rev-parse --git-common-dir)/.."

# Merge
git merge --no-ff "$feature_branch" -m "merge: $feature_branch"
git push

# Cleanup
git worktree remove "$worktree_path" --force
git branch -d "$feature_branch"
```

Report: "Merged `<feature_branch>` into `<base_branch>`, pushed, worktree cleaned up."

### Step 4B: Create PR (protected)

```bash
feature_branch=$(git branch --show-current)
worktree_path=$(pwd)

# Create PR
gh pr create --title "<generate from commits>" --body "<summary of changes>"

# Cleanup worktree only (code is on remote, worktree no longer needed)
# Do NOT delete local branch - PR hasn't merged yet
cd "$(git rev-parse --git-common-dir)/.."
git worktree remove "$worktree_path" --force
```

Report: "PR created: <url>. Worktree cleaned up. Local branch kept until PR merges."

## Edge Cases
- **Uncommitted changes in main worktree:** Before merge (4A), check `git -C <main-tree> status --porcelain`. If dirty, warn user and abort merge.
- **Merge conflict (4A):** If `git merge` fails, abort with `git merge --abort`, fall back to Step 4B (create PR instead).
- **No gh CLI:** Skip protection check, skip PR creation. Just commit + push + warn user to handle merge manually.
