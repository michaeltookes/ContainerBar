# DockerBar Technical Decisions

This document records major technical decisions made during development.

---

## January 17, 2026 - Decision: Project Structure

**Context**: Need to establish the Swift package structure for DockerBar

**Options**:
1. Single target with all code
2. Separate DockerBar (app) and DockerBarCore (library) targets
3. Additional targets for CLI, widgets, etc.

**Decision**: Option 2 - Two main targets

**Rationale**:
- Follows CodexBar pattern
- Allows core logic to be tested independently
- Core library has no UI dependencies
- Enables future reuse (CLI tool, widgets)
- Clear separation of concerns

**Agents Involved**: @BUILD_LEAD

---

## January 17, 2026 - Decision: State Management Pattern

**Context**: Need reactive state management for UI updates

**Options**:
1. Combine framework with @Published
2. Swift Observation framework with @Observable
3. Custom observable pattern

**Decision**: Option 2 - Swift Observation (@Observable)

**Rationale**:
- Modern Swift pattern, future-proof
- Matches CodexBar's approach
- Automatic UI updates without manual subscription
- @MainActor isolation for thread safety
- Cleaner syntax than Combine

**Agents Involved**: @BUILD_LEAD

---

## Decision Template

```markdown
## [Date] - Decision: [Title]

**Context**: Problem description

**Options**:
1. Option A
2. Option B

**Decision**: Chose X

**Rationale**: Why

**Agents Involved**: @AGENT1, @AGENT2
```
