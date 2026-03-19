Automated PR review comment handler. Fetches review comments, triages them, fixes code for valid ones, pushes back on invalid ones, and resolves all threads — while maintaining global context integrity via PR Blueprint.

## Phase 1: PR Blueprint — Build Global Context

Before touching ANY code, build a complete understanding of the PR.

1. Identify the PR:
```bash
# If user provides PR URL/number, use it. Otherwise detect from current branch:
gh pr view --json number,title,body,headRefName,baseRefName,files
```

2. Fetch the full diff:
```bash
gh pr diff <PR_NUMBER>
```

3. Write the **PR Blueprint** to `/tmp/fixpr-blueprint.md`:

```markdown
# PR Blueprint

## Original Intent
<one-line: what this PR is trying to achieve>

## Architecture Decisions
<key design choices made in this PR — WHY things are done this way>

## File Roles
| File | Role | Protected Code |
|------|------|----------------|
| <path> | <what this file does in the PR> | <critical sections that must NOT be changed> |

## Invariants
- <list of things that must remain true after any modification>
```

**Protected Code**: Sections marked in the Blueprint's "Protected Code" column are off-limits unless a review comment explicitly targets them. This prevents accidental regressions when fixing unrelated comments.

4. Read the Blueprint back and confirm it captures the PR's full intent before proceeding.

## Phase 2: Fetch & Triage Review Comments

1. Fetch all pending review threads:
```bash
gh pr view <PR_NUMBER> --json reviewThreads --jq '.reviewThreads[] | select(.isResolved == false)'
```

2. For each unresolved thread, classify:
   - **AGREE** — the reviewer's suggestion is correct, code should be changed
   - **PUSHBACK** — the reviewer misunderstood or the current code is intentionally designed this way

3. Write triage results to `/tmp/fixpr-triage.md`:
```markdown
## Triage

| # | File:Line | Reviewer Says | Verdict | Reason |
|---|-----------|--------------|---------|--------|
| 1 | path:L42 | "rename this" | AGREE | naming is indeed unclear |
| 2 | path:L88 | "remove this" | PUSHBACK | intentional per Blueprint invariant #2 |
```

## Phase 3: Fix Code — Blueprint-Guarded Modifications

For each AGREE item, apply the fix with Blueprint protection:

1. **Re-read Blueprint before EVERY modification** — open `/tmp/fixpr-blueprint.md` and verify the planned change does not violate any invariant or touch Protected Code unrelated to this comment.

2. Make the minimal code change to address the reviewer's comment.

3. After each change, append status to `/tmp/fixpr-blueprint.md`:
```markdown
## Change Log
- [fixed] path:L42 — renamed variable per reviewer suggestion (Blueprint check: ✅ no invariant violated)
```

4. If a fix would violate a Blueprint invariant, STOP and re-classify as PUSHBACK with explanation.

**Anti-drift rule**: If you have made ≥ 3 changes without re-reading the Blueprint, STOP immediately, re-read `/tmp/fixpr-blueprint.md`, and verify all changes so far are consistent with the original PR intent.

## Phase 4: Reply & Resolve Threads

For each triaged comment:

### AGREE items (already fixed):
1. Reply with what was changed:
```bash
gh api graphql -f query='mutation {
  addPullRequestReviewComment(input: {
    pullRequestReviewId: "<REVIEW_ID>",
    body: "Fixed: <brief description of change>",
    inReplyTo: "<COMMENT_NODE_ID>"
  }) { comment { id } }
}'
```

2. Resolve the thread:
```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: {
    threadId: "<THREAD_NODE_ID>"
  }) { thread { isResolved } }
}'
```

### PUSHBACK items:
1. Reply with respectful explanation referencing the PR's design intent:
```bash
gh api graphql -f query='mutation {
  addPullRequestReviewComment(input: {
    pullRequestReviewId: "<REVIEW_ID>",
    body: "This is intentional — <explanation referencing Blueprint>. Happy to discuss further.",
    inReplyTo: "<COMMENT_NODE_ID>"
  }) { comment { id } }
}'
```

2. Resolve the thread (pushback is still a resolution):
```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: {
    threadId: "<THREAD_NODE_ID>"
  }) { thread { isResolved } }
}'
```

## Phase 5: Verify & Push

1. Run project-specific checks (lint, typecheck, tests) if applicable.

2. Re-read the PR Blueprint one final time — confirm all changes align with original intent.

3. Verify all threads are resolved:
```bash
gh pr view <PR_NUMBER> --json reviewThreads --jq '[.reviewThreads[] | select(.isResolved == false)] | length'
# Expected: 0
```

4. Commit and push:
```bash
git add -A
git commit -m "fix: address PR review comments"
git push
```

5. Report summary to user:
```markdown
## @fixpr Summary
- **AGREE (fixed):** N comments
- **PUSHBACK (replied):** M comments
- **All threads resolved:** ✅/❌
- **Blueprint violations:** none / <list>
```

---
User's task:
(The user's next message provides the PR URL or number. If invoked without arguments, detect PR from current branch.)
