Checkout a branch in a submodule, with fuzzy search support. (CK = Checkout)

## Scope
Operates on the current submodule or the submodule specified by the user.

## Steps

### Step 1: Determine Target Submodule

If user specifies a submodule name, use it. Otherwise detect from current directory:

```bash
# Check if we're inside a submodule
sm_path=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -n "$sm_path" ]; then
  echo "IN_SUBMODULE=true"
else
  # List available submodules for user to pick
  git submodule --quiet foreach 'echo $sm_path'
fi
```

### Step 2: Fuzzy Search Branches

If user provided a branch name (or partial name after @ck):

```bash
input="<user_input>"

# Fetch latest branches
git fetch origin --prune --quiet 2>/dev/null

# Search: local branches first, then remote
echo "=== Local branches ==="
git branch --list "*${input}*" --sort=-committerdate | head -10

echo "=== Remote branches ==="
git branch -r --list "*${input}*" --sort=-committerdate | head -10
```

Show matches to user. If multiple matches, let user pick. If exactly one match, confirm and proceed.

If user provided NO branch name, show recent branches:

```bash
echo "=== Recent branches (last 10) ==="
git branch -r --sort=-committerdate | head -10
```

### Step 3: Checkout

Two modes based on user intent:

**Mode A: Direct checkout (switch submodule's current branch)**
```bash
git checkout <branch>
```

**Mode B: Create worktree (for development work)**
```bash
branch="<selected_branch>"
sm_name=$(basename $(pwd))
wt_name="${sm_name}-$(echo $branch | sed 's#origin/##; s#/#-#g')"
wt_path="worktrees/${wt_name}"

# Create worktree at project root level
git worktree add "../../worktrees/${wt_name}" -b "$(echo $branch | sed 's#origin/##')" "$branch" 2>/dev/null \
  || git worktree add "../../worktrees/${wt_name}" "$branch"

echo "Worktree created: $wt_path (branch: $branch)"
```

Ask user which mode they want, default to Mode B (worktree) for feature branches.

## Edge Cases
- **Branch not found:** Show "No branches matching '<input>'. Did you mean:" with closest matches.
- **Worktree already exists for branch:** Warn and show existing worktree path.
- **Detached HEAD in submodule:** Warn user before checkout.

---
User's message (the text after @ck):
