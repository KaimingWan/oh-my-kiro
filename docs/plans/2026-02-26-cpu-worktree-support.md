# @cpu Worktree Support Implementation Plan

**Goal:** Enhance `@cpu` command to detect worktree context and automatically handle the full lifecycle: commit → push → merge-to-main (or PR if protected) → cleanup worktree.

**Non-Goals:** Not changing ralph_loop.py or parallel execution. Not adding new scripts — this is a command doc change only. Not handling multi-worktree batch scenarios (that's ralph_loop's job).

**Architecture:** Modify `commands/cpu.md` to add worktree detection logic. When in a worktree, detect branch protection via `gh api`, then either (a) merge locally + push + cleanup, or (b) create PR + cleanup. All logic is agent-executed bash — no Python scripts needed.

**Tech Stack:** bash, git, gh CLI

## Review

Round 1 (4 reviewers parallel):
- Goal Alignment: APPROVE — all scenarios covered, execution order valid
- Verify Correctness: APPROVE — 7/7 verify commands sound, correct/broken exit codes diverge
- Completeness: APPROVE — all logical branches and error paths covered
- Clarity: APPROVE — content fully specified verbatim, no ambiguity for executor

## Tasks

### Task 1: Rewrite commands/cpu.md with worktree support

**Files:**
- Modify: `commands/cpu.md`

**Step 1: Write failing test**

Verify the new cpu.md contains required keywords for worktree handling:

```bash
grep -q 'worktree' commands/cpu.md && \
grep -q 'protection' commands/cpu.md && \
grep -q 'gh pr create' commands/cpu.md && \
grep -q 'git worktree remove' commands/cpu.md
```

Expected: FAIL (current cpu.md has none of these)

**Step 2: Write the new cpu.md**

Replace `commands/cpu.md` with the following content:

```markdown
Commit all changes, push to remote, and complete branch lifecycle. (CPU = Commit Push Update-readme)

## Scope
Only operate on the current project (where AGENTS.md lives). NEVER cd into or commit/push other repositories.

## Steps

### Step 1: Stage & Commit
1. `git add -A && git status --short` — show what's staged
2. Ask user for commit message if not provided, or generate one from the diff
3. `git commit -m "<message>"`
4. `git push`
5. Report: commit hash + push result

### Step 2: Detect Worktree

Check if currently inside a git worktree:

​```bash
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
​```

- If **not in worktree** → STOP here. Done (original behavior).
- If **in worktree** → continue to Step 3.

### Step 3: Check Branch Protection

​```bash
# Extract owner/repo from remote
remote_url=$(git remote get-url origin)
repo_slug=$(echo "$remote_url" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
gh api "repos/${repo_slug}/branches/${base_branch}/protection" 2>&1
​```

- **404 (not protected)** → Step 4A (merge locally)
- **200 (protected)** → Step 4B (create PR)
- **gh CLI error / no auth** → fall back to Step 4B (safer default)

### Step 4A: Merge to Main (unprotected)

​```bash
feature_branch=$(git branch --show-current)
worktree_path=$(pwd)

# Switch to main working tree
cd "$(git rev-parse --git-common-dir)/.."

# Merge
git merge --no-ff "$feature_branch" -m "merge: $feature_branch"
git push

# Cleanup
git worktree remove "$worktree_path" --force
git branch -D "$feature_branch"
​```

Report: "Merged `<feature_branch>` into `<base_branch>`, pushed, worktree cleaned up."

### Step 4B: Create PR (protected)

​```bash
feature_branch=$(git branch --show-current)
worktree_path=$(pwd)

# Create PR
gh pr create --title "<generate from commits>" --body "<summary of changes>"

# Cleanup worktree (code is on remote, worktree no longer needed)
cd "$(git rev-parse --git-common-dir)/.."
git worktree remove "$worktree_path" --force
git branch -D "$feature_branch"
​```

Report: "PR created: <url>. Worktree cleaned up. Branch will be deleted when PR merges (use `--delete-branch` on merge)."

## Edge Cases
- **Uncommitted changes in main worktree:** Before merge (4A), check `git -C <main-tree> status --porcelain`. If dirty, warn user and abort merge.
- **Merge conflict (4A):** If `git merge` fails, abort with `git merge --abort`, fall back to Step 4B (create PR instead).
- **No gh CLI:** Skip protection check, skip PR creation. Just commit + push + warn user to handle merge manually.
```

**Step 3: Run verify — confirm it passes**

```bash
grep -q 'worktree' commands/cpu.md && \
grep -q 'protection' commands/cpu.md && \
grep -q 'gh pr create' commands/cpu.md && \
grep -q 'git worktree remove' commands/cpu.md
```

Expected: PASS

**Step 4: Commit**

```bash
git add commands/cpu.md
git commit -m "feat(cpu): add worktree support with auto-merge/PR flow"
```

## Errors

| Error | Task | Attempt | Resolution |
|-------|------|---------|------------|

## Findings
<!-- Append-only during execution -->

## Checklist

- [ ] cpu.md 包含 worktree 检测逻辑 | `grep -q 'git rev-parse --git-common-dir' commands/cpu.md`
- [ ] cpu.md 包含 branch protection 检测 | `grep -q 'protection' commands/cpu.md`
- [ ] cpu.md 包含无保护时本地 merge 流程 | `grep -q 'git merge --no-ff' commands/cpu.md`
- [ ] cpu.md 包含有保护时 PR 创建流程 | `grep -q 'gh pr create' commands/cpu.md`
- [ ] cpu.md 包含 worktree 清理 | `grep -q 'git worktree remove' commands/cpu.md`
- [ ] cpu.md 包含 merge 冲突回退到 PR | `grep -q 'merge --abort' commands/cpu.md`
- [ ] cpu.md 包含主 worktree dirty 检查 | `grep -q 'porcelain' commands/cpu.md`
