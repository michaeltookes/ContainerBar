# DockerBar Open Questions

This document tracks questions needing discussion or resolution.

---

## Open Questions

*No open questions at this time.*

---

## Resolved Questions

### January 17, 2026 - Question: Which Swift version to target?

**Question**: Should we target Swift 5.9 or Swift 6.0?

**Context**: Swift 6.0 has strict concurrency checking which may require more work but provides better safety.

**Resolution**: Target Swift 6.0 - it's specified in the DESIGN_DOCUMENT.md and provides strict concurrency for thread safety.

**Status**: Resolved

---

## Question Template

```markdown
## [Date] - Question: [Title]

@TAGGED_AGENT - Description

**Context**: Additional background

**Proposed Solutions**:
- Solution 1
- Solution 2

**Status**: Open | Resolved
```
