# Debugging Reference

## LSP Tool Recipes

### get_diagnostics — Compiler Errors & Warnings

Get all errors, warnings, and hints for a file:
```
get_diagnostics(file_path="src/main.py")
```
Use FIRST when debugging — gives exact error locations and types.
Use AFTER fix — verify zero new diagnostics introduced.

### search_symbols — Find Symbol Definitions

Find where a function, class, or variable is defined:
```
search_symbols(symbol_name="processOrder", symbol_type="function")
```
Use when you know the name but not the location.

### goto_definition — Navigate to Implementation

Jump to where a symbol is actually defined:
```
goto_definition(file_path="src/handler.py", row=42, column=15)
```
Use after search_symbols to read the actual implementation.
**Iron Law: No goto_definition = No modify.**

### find_references — Find All Usage Sites

Find everywhere a symbol is used:
```
find_references(file_path="src/models.py", row=10, column=8)
```
Use before refactoring to understand impact.
**Iron Law: No find_references = No refactor.**

### get_hover — Type Information

Get type and documentation at a position:
```
get_hover(file_path="src/utils.py", row=25, column=12)
```
Use to understand types without reading full implementation.

### Typical Workflow

```
1. get_diagnostics → identify errors
2. search_symbols → find relevant code
3. goto_definition → read implementation
4. find_references → understand usage
5. get_hover → check types
6. [fix code]
7. get_diagnostics → verify fix (zero new diagnostics)
```

## Structural Code Search (pattern_search)

Use `pattern_search` for AST-aware bug pattern detection — finds structural matches that grep misses.

### Find subprocess calls without timeout
```
pattern_search(pattern='subprocess.run($$$ARGS)', language='python')
```
Then inspect each match for missing `timeout=` parameter.

### Find unchecked error returns (Go)
```
pattern_search(pattern='$VAR, _ := $FUNC($$$)', language='go')
```

### Find bare except clauses (Python)
```
pattern_search(pattern='except: $$$BODY', language='python')
```

### Find TODO/FIXME in code (not comments)
```
pattern_search(pattern='$VAR = "TODO"', language='python')
```
For comments, use grep instead — pattern_search matches code structure, not comments.

### When to use pattern_search vs grep
- **pattern_search**: structural code patterns (function signatures, error handling, API calls)
- **grep**: literal text, comments, config values, log messages

## Multi-Component Diagnostic Patterns

### Boundary Instrumentation

When system has multiple components, add diagnostic logging at each boundary:

```bash
# Layer 1: Workflow
echo "=== Secrets available in workflow: ==="
echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"

# Layer 2: Build script
echo "=== Env vars in build script: ==="
env | grep IDENTITY || echo "IDENTITY not in environment"

# Layer 3: Signing script
echo "=== Keychain state: ==="
security list-keychains
security find-identity -v

# Layer 4: Actual signing
codesign --sign "$IDENTITY" --verbose=4 "$APP"
```

This reveals which layer fails (secrets → workflow ✓, workflow → build ✗).

### Backward Tracing

When error is deep in call stack:
1. Start at the error
2. Use `goto_definition` to navigate to the function
3. Use `find_references` to find all callers
4. Trace backward: who called this with bad data?
5. Keep going until you find the source
6. Fix at source, not at symptom

### Condition-Based Waiting

Replace arbitrary timeouts with condition polling:
```bash
# Bad: sleep 30
# Good:
for i in $(seq 1 60); do
  curl -s http://localhost:8080/health && break
  sleep 1
done
```
