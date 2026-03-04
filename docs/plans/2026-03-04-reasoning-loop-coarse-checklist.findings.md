# Findings

## Codebase Patterns

- **build_prompt structure:** Single f-string return. New prompt sections append before the closing `"""`. All dynamic content uses f-string interpolation with variables computed above the return.
- **Test pattern:** Tests import `build_prompt` and `PlanFile` directly, create a minimal plan in `tmp_path`, call `build_prompt()`, and assert on string content. No subprocess needed for prompt tests.
- **Plan hook timing:** The verify-before-checkoff hook requires the verify command to be the most recent `execute_bash` call before the `str_replace` that marks `- [x]`. Running it earlier and doing other tool calls in between triggers the block.
