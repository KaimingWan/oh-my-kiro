Automated PR fixer: fetch all review comments, triage each one, fix or pushback, reply + resolve every thread. Zero unresolved threads when done.

## Step 1: Understand the PR

```bash
gh pr view <PR> --json number,title,body,headRefName,baseRefName,files,additions,deletions
gh pr diff <PR>
```

Read the full diff. Understand what the PR does and why — this context guards against drift when fixing individual comments.

## Step 2: Fetch ALL Unresolved Review Threads

**This step is MANDATORY. Do NOT skip it.**

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!) {
  repository(owner:$owner,name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          comments(first:5) {
            nodes { id body author { login } path line }
          }
        }
      }
    }
  }
}' -f owner='<OWNER>' -f repo='<REPO>' -F pr='<PR_NUMBER>'
```

Filter to unresolved threads. If zero unresolved → report "nothing to fix" and stop.

## Step 3: Triage Every Thread

For each unresolved thread, decide:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **AGREE** | Reviewer is right | Fix the code |
| **PUSHBACK** | Current code is intentional or reviewer misunderstood | Explain why, don't change code |

Show the triage table to the user before proceeding:

```
| # | Thread ID | File:Line | Comment (summary) | Verdict | Reason |
```

## Step 4: Fix Code (AGREE items only)

For each AGREE item:
1. Make the minimal code change
2. Verify the fix doesn't break other parts of the PR

After all AGREE fixes: run build/lint/typecheck if applicable.

## Step 5: Reply + Resolve EVERY Thread

**CRITICAL: Both AGREE and PUSHBACK threads get a reply AND a resolve. No exceptions.**

### For AGREE threads:
```bash
# Reply with what was fixed
gh api graphql -f query='mutation($tid:ID!,$body:String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId:$tid, body:$body}) {
    comment { id }
  }
}' -f tid='<THREAD_ID>' -f body='Fixed: <what changed>'

# Resolve
gh api graphql -f query='mutation($tid:ID!) {
  resolveReviewThread(input:{threadId:$tid}) { thread { isResolved } }
}' -f tid='<THREAD_ID>'
```

### For PUSHBACK threads:
```bash
# Reply with explanation
gh api graphql -f query='mutation($tid:ID!,$body:String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId:$tid, body:$body}) {
    comment { id }
  }
}' -f tid='<THREAD_ID>' -f body='Intentional: <explanation>. Happy to discuss.'

# Resolve (pushback is still a resolution)
gh api graphql -f query='mutation($tid:ID!) {
  resolveReviewThread(input:{threadId:$tid}) { thread { isResolved } }
}' -f tid='<THREAD_ID>'
```

## Step 6: Verify Zero Unresolved + Push

```bash
# Must be 0
gh api graphql ... --jq '[.nodes[] | select(.isResolved==false)] | length'
```

Commit, push, report:

```
## @fixpr Summary
- AGREE (fixed): N
- PUSHBACK (replied): M
- All threads resolved: ✅
```

---
User's task:
(User provides PR URL/number. If none, detect from current branch.)
