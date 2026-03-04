---
name: debugging
description: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes
---

# Systematic Debugging

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

### Three Iron Laws of Code Debugging

1. **No goto_definition = No modify** — Don't change code you haven't navigated to its definition
2. **No find_references = No refactor** — Don't refactor without knowing all usage sites
3. **No get_diagnostics = No claim fixed** — Don't claim a fix without verifying zero new diagnostics

## Tool Decision Matrix

| Bug Type | Tool Sequence | Why |
|----------|--------------|-----|
| Compile/type error | `get_diagnostics` → `goto_definition` → `get_hover` | Diagnostics pinpoint error; definition shows context; hover reveals types |
| Wrong behavior | `search_symbols` → `find_references` → `goto_definition` | Find the symbol, trace all callers, read implementation |
| Unknown codebase | `get_document_symbols` → `goto_definition` → `get_hover` | Map file structure, navigate to definitions, understand types |
| Refactor broke something | `find_references` → `get_diagnostics` → `search_symbols` | Find all usage sites, check for new errors, locate related symbols |
| Test failure | `get_diagnostics` → `search_symbols` → `find_references` | Check compiler errors first, find test subject, trace dependencies |

**When to use grep instead:** Only for searching comments, string literals, config values, or non-code files.

## When to Use

Use for ANY technical issue:
- Test failures
- Bugs in production
- Unexpected behavior
- Performance problems
- Build failures
- Integration issues

**Use this ESPECIALLY when:**
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- Previous fix didn't work
- You don't fully understand the issue

**Don't skip when:**
- Issue seems simple (simple bugs have root causes too)
- You're in a hurry (rushing guarantees rework)
- Manager wants it fixed NOW (systematic is faster than thrashing)

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

**Step 0: Check Past Episodes**
- Read `knowledge/episodes.md` for similar past bugs
- Past mistakes often repeat — check before investigating from scratch

**Step 1: Run get_diagnostics First**
- Run `get_diagnostics` on the failing file(s) to get compiler errors, warnings, hints
- This gives you the exact error locations and types — far more precise than reading logs

**Step 2: Use search_symbols to Find Relevant Code**
- Use `search_symbols` to locate the function/class/variable involved in the error
- Follow up with `goto_definition` to read the actual implementation
- Use `find_references` to understand all callers and usage sites

**Step 3: Read Error Messages Carefully**
- Don't skip past errors or warnings
- They often contain the exact solution
- Read stack traces completely
- Note line numbers, file paths, error codes

**Step 4: Reproduce Consistently**
- Can you trigger it reliably?
- What are the exact steps?
- Does it happen every time?
- If not reproducible → gather more data, don't guess

**Step 5: Check Recent Changes**
- What changed that could cause this?
- Git diff, recent commits
- New dependencies, config changes
- Environmental differences

**Step 6: Gather Diagnostic Evidence**

You MUST produce a **Diagnostic Evidence** summary before moving to Phase 2:

```
Diagnostic Evidence:
- get_diagnostics: [what errors/warnings were found]
- search_symbols: [what symbols were located]
- find_references: [what callers/usage sites were found]
- get_hover: [what type information was revealed]
- Root cause hypothesis: [your conclusion based on above]
```

Without this evidence, you cannot proceed.

**Step 7: Gather Evidence in Multi-Component Systems**

WHEN system has multiple components (CI → build → signing, API → service → database):

BEFORE proposing fixes, add diagnostic instrumentation:
```
For EACH component boundary:
  - Log what data enters component
  - Log what data exits component
  - Verify environment/config propagation
  - Check state at each layer

Run once to gather evidence showing WHERE it breaks
THEN analyze evidence to identify failing component
THEN investigate that specific component
```

**Step 8: Trace Data Flow**

WHEN error is deep in call stack:
- Use `goto_definition` to navigate to the error source
- Use `find_references` to trace callers backward
- Where does bad value originate?
- Keep tracing up until you find the source
- Fix at source, not at symptom

### Phase 2: Pattern Analysis

**Find the pattern before fixing:**

1. **Find Working Examples**
   - Locate similar working code in same codebase
   - Use `search_symbols` to find similar patterns
   - What works that's similar to what's broken?

2. **Compare Against References**
   - If implementing pattern, read reference implementation COMPLETELY
   - Don't skim - read every line
   - Understand the pattern fully before applying

3. **Identify Differences**
   - What's different between working and broken?
   - List every difference, however small
   - Don't assume "that can't matter"

4. **Understand Dependencies**
   - What other components does this need?
   - What settings, config, environment?
   - What assumptions does it make?

### Phase 3: Hypothesis and Testing

**Scientific method:**

1. **Form Single Hypothesis**
   - State clearly: "I think X is the root cause because Y"
   - Write it down
   - Be specific, not vague

2. **Test Minimally**
   - Make the SMALLEST possible change to test hypothesis
   - One variable at a time
   - Don't fix multiple things at once

3. **Verify Before Continuing**
   - Did it work? Yes → Phase 4
   - Didn't work? Form NEW hypothesis
   - DON'T add more fixes on top

4. **When You Don't Know**
   - Say "I don't understand X"
   - Don't pretend to know
   - Ask for help
   - Research more

### Phase 4: Implementation

**Fix the root cause, not the symptom:**

1. **Run get_diagnostics Before Fix (baseline)**
   - Record current diagnostics count and details
   - This is your "before" snapshot

2. **Create Failing Test Case**
   - Simplest possible reproduction
   - Automated test if possible
   - MUST have before fixing

3. **Implement Single Fix**
   - Address the root cause identified
   - ONE change at a time
   - No "while I'm here" improvements
   - No bundled refactoring

4. **Run get_diagnostics After Fix (verify)**
   - Compare with baseline: new diagnostics must be 0
   - All original diagnostics should be resolved or unchanged
   - If new diagnostics appeared, your fix introduced problems — revert

5. **Verify Fix**
   - Test passes now?
   - No other tests broken?
   - Issue actually resolved?

6. **If Fix Doesn't Work**
   - STOP
   - Count: How many fixes have you tried?
   - If < 3: Return to Phase 1, re-analyze with new information
   - **If ≥ 3: STOP and question the architecture (step 7 below)**
   - DON'T attempt Fix #4 without architectural discussion

7. **If 3+ Fixes Failed: Question Architecture**

   **Pattern indicating architectural problem:**
   - Each fix reveals new shared state/coupling/problem in different place
   - Fixes require "massive refactoring" to implement
   - Each fix creates new symptoms elsewhere

   **STOP and question fundamentals:**
   - Is this pattern fundamentally sound?
   - Are we "sticking with it through sheer inertia"?
   - Should we refactor architecture vs. continue fixing symptoms?

   **Discuss with your human partner before attempting more fixes**

## Red Flags - STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Pattern says X but I'll adapt it differently"
- "Here are the main problems: [lists fixes without investigation]"
- Proposing solutions before tracing data flow
- **"One more fix attempt" (when already tried 2+)**
- **Each fix reveals new problem in different place**
- **Using grep to find code instead of search_symbols/find_references**

**ALL of these mean: STOP. Return to Phase 1.**

**If 3+ fixes failed:** Question the architecture (see Phase 4.7)

## Your Human Partner's Signals You're Doing It Wrong

**Watch for these redirections:**
- "Is that not happening?" - You assumed without verifying
- "Will it show us...?" - You should have added evidence gathering
- "Stop guessing" - You're proposing fixes without understanding
- "Ultrathink this" - Question fundamentals, not just symptoms
- "We're stuck?" (frustrated) - Your approach isn't working

**When you see these:** STOP. Return to Phase 1.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write test after confirming fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question pattern, don't fix again. |
| "I'll just grep for it" | grep is text matching. Use LSP tools for semantic code analysis. |

## Quick Reference

| Phase | Key Activities | Success Criteria |
|-------|---------------|------------------|
| **1. Root Cause** | get_diagnostics, search_symbols, find_references, reproduce, gather evidence | Diagnostic Evidence produced |
| **2. Pattern** | Find working examples, compare | Identify differences |
| **3. Hypothesis** | Form theory, test minimally | Confirmed or new hypothesis |
| **4. Implementation** | Pre/post get_diagnostics, create test, fix, verify | Bug resolved, zero new diagnostics |

## When Process Reveals "No Root Cause"

If systematic investigation reveals issue is truly environmental, timing-dependent, or external:

1. You've completed the process
2. Document what you investigated
3. Implement appropriate handling (retry, timeout, error message)
4. Add monitoring/logging for future investigation

**But:** 95% of "no root cause" cases are incomplete investigation.

## Supporting Techniques

These techniques are part of systematic debugging and available in this directory:

- **`root-cause-tracing.md`** - Trace bugs backward through call stack to find original trigger
- **`defense-in-depth.md`** - Add validation at multiple layers after finding root cause
- **`condition-based-waiting.md`** - Replace arbitrary timeouts with condition polling

**Related skills:**
- **superpowers:test-driven-development** - For creating failing test case (Phase 4, Step 2)
- **superpowers:verification-before-completion** - Verify fix worked before claiming success
