# Java Coding Standards

> Prescriptive rules for Agent writing Java code. Loaded when touching Java files.
> Companion to `java-architect.md` (Spring Boot tech stack reference).

## Effective Java

- Prefer static factory methods over public constructors
- Use Builder pattern when constructor has more than 3 parameters
- Use `record` for pure data carriers (DTOs, value objects) — Java 16+
- Prefer immutability: make fields `final`, do not provide setters
- Prefer composition over inheritance
- Prefer interfaces over abstract classes
- Use `sealed class` to restrict inheritance hierarchy — Java 17+
- Never use raw types — always parameterize generics
- Return empty collections instead of null
- Use `Optional` for return values that may be absent — never for fields or parameters
- Use enums instead of int/String constants
- Minimize mutability — fewer moving parts, fewer bugs

## Clean Code

- Do one thing per method — Single Responsibility Principle
- Keep methods short, typically under 20 lines — split when longer
- Use self-documenting names: nouns for classes, verbs for methods, `is/has/can` for booleans
- Never use boolean flag parameters — split into two methods
- Never swallow exceptions: catch must log or rethrow
- Never catch `Exception` or `Throwable` — use specific exception types
- Must include exception object in log: `log.error("message", e)` not `log.error("message")`
- No `System.out.println` — use SLF4J logger
- Use comments to explain WHY, not WHAT — code should be self-explanatory
- No premature abstraction (YAGNI) — solve the problem at hand, abstract when needed

## Clean Architecture

- Dependency direction: outer layers → inner layers, never reverse
- No business logic in Controller or Interceptor — delegate to Service
- Depend on interfaces, not concrete implementations in Service layer
- Prefer constructor injection over `@Autowired` field injection
- Do not leak DTO/VO into domain layer

## Distributed Systems

- Never mix external API calls and local DB operations in the same `@Transactional`
- Do reversible operations first, irreversible operations last
- Must consider idempotency for all write operations
- Do not rely on single-machine in-memory cache for consistency in multi-node systems
- Must have timeout and retry strategy for cross-service calls

## Testing

- Mockito matchers must be consistent: all matchers or all concrete values, never mix
- Do not mock value objects (records, DTOs) — construct them directly
- Use naming convention: `methodName_condition_expectedResult`
- Each test verifies exactly one behavior
- Prefer specific arguments in `verify()` — avoid `any()` unless truly needed

## Agent Workflow

- Before modifying an interface: find-references to list all implementations and callers
- After modifying an interface: immediately run `mvn compile -pl <module> -am`
- After all changes: run `mvn clean test` — do not trust incremental compilation
- Before complex refactoring (≥3 files): write a plan, wait for user confirmation
- Before committing: run `git diff --stat` to confirm change scope matches intent
- Before creating a new class/interface: search if a similar abstraction already exists
