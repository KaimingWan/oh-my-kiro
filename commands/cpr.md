Commit all changes, push to remote, and create a Pull Request. (CPR = Commit Push PR)

## Scope
Only operate on the current git repository. NEVER cd into or commit/push other repositories.

## Steps

### Step 1: Stage & Commit
1. `git add -A && git status --short` — show what's staged
2. Ask user for commit message if not provided, or generate one from the diff
3. `git commit -m "<message>"`
4. `git push`
5. Report: commit hash + push result

### Step 2: Detect PR Target Branch

```bash
current_branch=$(git branch --show-current)

# 1. Check reflog for source branch (works for worktree branches)
created_from=$(git reflog show "$current_branch" --format="%gs" | tail -1 | sed 's/.*Created from //')
base=$(echo "$created_from" | sed 's#refs/remotes/origin/##; s#refs/heads/##')

# 2. If source == self (created from remote tracking branch), fallback to remote default
if [ "$base" = "$current_branch" ] || [ -z "$base" ]; then
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
  [ -z "$base" ] && base="main"
fi

echo "PR_TARGET=$base"
```

Show the detected target branch to user and ask for confirmation:
- "PR target: `<base>`. Confirm? (or specify a different branch)"
- If user provides a different branch, use that instead.

### Step 3: Create PR

```bash
gh pr create --base "$base" --title "<generate from commits>" --body "<summary of changes>"
```

Report: "PR created: <url>. Target: `<base>`."

### Step 4: Worktree Cleanup (only if in worktree)

```bash
wt_dir=$(git rev-parse --git-common-dir 2>/dev/null)
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [ "$wt_dir" != "$git_dir" ]; then
  worktree_path=$(pwd)
  cd "$(git worktree list | head -1 | awk '{print $1}')"
  git worktree remove "$worktree_path" --force
  echo "Worktree cleaned up."
fi
```

## Edge Cases
- **No gh CLI:** Warn user, skip PR creation. Just commit + push.
- **No changes to commit:** Skip commit, still create PR if there are pushed commits not yet in a PR.
- **User on main/default branch:** Warn "You're on the default branch, PR doesn't make sense." and abort.

---
User's message (the text after @cpr):
