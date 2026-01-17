---
  type: agent
---

# DockerBar Project - Master Agent Coordinator

**Version**: 1.0  
**Project**: DockerBar - macOS Menu Bar Docker Container Monitor  
**Last Updated**: January 16, 2026

---

## Mission Statement

Build a production-ready macOS menu bar application that provides instant access to Docker container monitoring and management. The application must be secure, performant, native, and delightful to use.

**Success Criteria:**
- ✅ Menu opens in <100ms with container list displayed
- ✅ Stats update with <1 second latency
- ✅ Memory footprint under 50MB
- ✅ CPU usage <1% when idle
- ✅ Successful connection to remote Docker daemon via TLS
- ✅ Graceful handling of network interruptions
- ✅ Production-ready code quality (90%+ test coverage)
- ✅ Comprehensive documentation
- ✅ Zero critical security vulnerabilities

---

## Project Overview

### What We're Building

DockerBar is a lightweight macOS menu bar application inspired by CodexBar's elegant architecture. It monitors Docker containers running on local or remote hosts, displaying real-time metrics and providing quick management actions—all from the macOS menu bar without opening a browser.

### Core Values

1. **Native Experience** - Feels like a first-class macOS citizen
2. **Security First** - All credentials in Keychain, TLS-verified connections
3. **Performance** - Lightweight, responsive, minimal resource usage
4. **Clean Code** - Follows Robert Martin's principles, maintainable, testable
5. **User Delight** - Polished UI, smooth animations, thoughtful UX

### Technical Foundation

- **Language**: Swift 6.0+ with strict concurrency
- **Frameworks**: SwiftUI + AppKit hybrid
- **Architecture**: Clean separation of concerns (UI → State → Service → API)
- **Patterns**: Provider Descriptor, Observable State, Strategy Pattern
- **Testing**: Comprehensive unit and integration tests
- **Documentation**: Inline docs, user guides, API documentation

---

## Agent Team Structure

This project is built by a coordinated team of specialized agents. Each agent has specific expertise and responsibilities, but all work together toward the common mission.

### Agent Hierarchy

```
AGENTS.md (YOU ARE HERE - Master Coordinator)
    │
    ├── BUILD_LEAD.md
    │   ├── Spawns: SWIFT_EXPERT.md
    │   └── Spawns: API_INTEGRATION.md
    │
    ├── UI_UX.md
    ├── SECURITY_COMPLIANCE.md
    ├── TEST_AGENT.md
    ├── REVIEW_AGENT.md
    └── DOC_AGENT.md
```

### Agent Roles & Responsibilities

| Agent | Primary Responsibility | Decision Authority |
|-------|------------------------|-------------------|
| **BUILD_LEAD** | Owns delivery, coordinates sub-agents, implements features | Technical architecture decisions |
| **SWIFT_EXPERT** | Swift 6 concurrency, AppKit/SwiftUI patterns | Language/framework best practices |
| **API_INTEGRATION** | Docker API client, networking, connection strategies | API implementation decisions |
| **UI_UX** | Design quality, user experience, visual polish | Design decisions (can be overridden by SECURITY) |
| **SECURITY_COMPLIANCE** | Security review, credential management, vulnerability prevention | **VETO POWER** on security decisions |
| **TEST_AGENT** | Quality assurance, test coverage, regression prevention | Quality gates (can block releases) |
| **REVIEW_AGENT** | Code review after every change, quality enforcement | Code quality standards |
| **DOC_AGENT** | Documentation, changelogs, user guides | Documentation completeness |

### Decision-Making Protocol

**Normal Decisions**: BUILD_LEAD makes day-to-day technical decisions

**Design Decisions**: UI_UX provides recommendations, BUILD_LEAD implements

**Security Decisions**: SECURITY_COMPLIANCE has **VETO POWER**
- If SECURITY says no, the answer is no
- Security concerns override all other considerations

**Quality Gates**: TEST_AGENT and REVIEW_AGENT must approve before code is considered complete
- TEST_AGENT: Minimum 80% test coverage, all tests passing
- REVIEW_AGENT: Code quality standards met, clean code principles followed

**Conflict Resolution**:
1. Agents discuss in `.agents/communications/open-questions.md`
2. If unresolved, BUILD_LEAD makes the call
3. If involves security, SECURITY_COMPLIANCE decides
4. If still unresolved, document both approaches and choose the safer/simpler one

---

## Project Phases & Milestones

### Phase 1: MVP Foundation (Weeks 1-2)

**Goal**: Basic menu bar app that can list and manage local Docker containers

**Deliverables**:
- ✅ Swift package structure (DockerBar + DockerBarCore)
- ✅ Menu bar status item with dropdown menu
- ✅ Docker API client (Unix socket support)
- ✅ Container listing and basic stats
- ✅ Start/stop/restart actions
- ✅ Settings window with host configuration

**Success Metric**: Can monitor and manage containers on local Docker daemon

### Phase 2: Remote & Polish (Weeks 3-4)

**Goal**: Production-ready with remote Docker support

**Deliverables**:
- ✅ TCP + TLS connection support
- ✅ Keychain integration for credentials
- ✅ Auto-refresh with configurable intervals
- ✅ Container log viewing
- ✅ Dynamic menu bar icon rendering
- ✅ Error handling and resilience

**Success Metric**: Can securely connect to remote Docker daemon on Beelink server

### Phase 3: Testing & Release (Weeks 5-6)

**Goal**: Tested, documented, ready for users

**Deliverables**:
- ✅ Comprehensive test suite (90%+ coverage)
- ✅ User documentation (README, troubleshooting)
- ✅ Code signing and notarization
- ✅ Auto-update mechanism (Sparkle)
- ✅ Performance validation

**Success Metric**: Ready for public release with confidence

### Future Phases

**Phase 4**: Multi-host support, SSH tunnels, image management  
**Phase 5**: Kubernetes, Podman, WidgetKit extension

---

## Coding Standards & Principles

All agents must adhere to these standards. REVIEW_AGENT enforces compliance.

### Robert Martin's Clean Code Principles

**1. Meaningful Names**
```swift
// ❌ Bad
var d: Date  // What does 'd' mean?
func proc() { }

// ✅ Good
var lastRefreshTimestamp: Date
func processContainerStats() { }
```

**2. Functions Should Do One Thing**
```swift
// ❌ Bad - does too much
func updateUI() {
    fetchContainers()
    parseData()
    updateStore()
    renderView()
}

// ✅ Good - single responsibility
func refresh() async {
    let containers = try await fetcher.fetchContainers()
    await updateStore(with: containers)
}
```

**3. Don't Repeat Yourself (DRY)**
- Extract common patterns into reusable functions
- Use protocol extensions for shared behavior
- Avoid copy-paste code

**4. Error Handling**
```swift
// ❌ Bad - swallowing errors
func connect() {
    try? apiClient.connect()
}

// ✅ Good - explicit error handling
func connect() async throws {
    do {
        try await apiClient.connect()
        isConnected = true
    } catch {
        logger.error("Connection failed: \(error)")
        throw DockerAPIError.connectionFailed
    }
}
```

**5. Comments Should Explain WHY, Not WHAT**
```swift
// ❌ Bad - obvious comment
// Set the container ID
container.id = "abc123"

// ✅ Good - explains reasoning
// Docker API returns names with leading '/', strip it for display
let displayName = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
```

### Swift 6 Concurrency Rules

**1. Always Use @MainActor for UI Updates**
```swift
@MainActor
@Observable
final class ContainerStore {
    var containers: [DockerContainer] = []
    
    func updateUI(with containers: [DockerContainer]) {
        // Safe - already on main actor
        self.containers = containers
    }
}
```

**2. Mark Types as Sendable When Appropriate**
```swift
// Value types crossing concurrency boundaries
public struct DockerContainer: Sendable, Codable {
    let id: String
    let name: String
}
```

**3. Use Structured Concurrency**
```swift
// ✅ Good - structured with TaskGroup
await withTaskGroup(of: ContainerStats?.self) { group in
    for container in containers {
        group.addTask {
            try? await fetchStats(for: container.id)
        }
    }
    
    for await stats in group {
        // Process stats
    }
}
```

### Code Organization

**Module Structure**:
```
DockerBarCore/          # Business logic (no UI dependencies)
├── Models/             # Data structures
├── API/                # Docker API client
├── Services/           # Business logic services
└── Strategies/         # Fetch strategies

DockerBar/              # macOS application
├── App/                # App lifecycle
├── Views/              # SwiftUI views
├── Controllers/        # AppKit controllers
└── Resources/          # Assets, strings
```

**File Size**: Keep files under 300 lines. Split larger files into extensions or separate concerns.

**Naming Conventions**:
- Types: `PascalCase` (ContainerStore, DockerAPIClient)
- Functions: `camelCase` (fetchContainers, updateUI)
- Constants: `camelCase` (maxRetryCount)
- Enums: `PascalCase` with lowercase cases (ContainerState.running)

---

## Communication Protocols

### Where Agents Communicate

All agent communication happens in `.agents/communications/`:

```
.agents/communications/
├── decisions.md          # Major technical decisions with rationale
├── open-questions.md     # Issues needing discussion/resolution
├── security-reviews.md   # Security findings and recommendations
├── ui-feedback.md        # UI/UX design suggestions and feedback
└── daily-standup.md      # What each agent accomplished today
```

### Communication Templates

**For Decisions (decisions.md)**:
```markdown
## [Date] - Decision: [Brief Title]

**Context**: What problem are we solving?

**Options Considered**:
1. Option A - Pros/Cons
2. Option B - Pros/Cons

**Decision**: We chose Option A

**Rationale**: Why we made this choice

**Agents Involved**: @BUILD_LEAD, @SECURITY_COMPLIANCE
```

**For Open Questions (open-questions.md)**:
```markdown
## [Date] - Question: [Brief Title]

**Question**: What should we do about X?

**Context**: Additional background

**Proposed Solutions**:
- Solution 1
- Solution 2

**Agents Tagged**: @UI_UX, @BUILD_LEAD

**Status**: Open | Resolved
```

**For Daily Standup (daily-standup.md)**:
```markdown
## [Date] - Daily Standup

### @BUILD_LEAD
- Completed: Implemented ContainerStore with @Observable pattern
- In Progress: Docker API client for Unix socket
- Blockers: None

### @SECURITY_COMPLIANCE
- Completed: Reviewed Keychain integration approach
- In Progress: TLS certificate validation logic
- Blockers: Need BUILD_LEAD to implement before I can test

[... other agents ...]
```

### When to Communicate

**Always Communicate**:
- Before making architectural decisions → `decisions.md`
- When stuck or need input → `open-questions.md`
- When finding security issues → `security-reviews.md`
- After completing daily work → `daily-standup.md`

**Don't Over-Communicate**:
- Routine implementation work (just do it)
- Following established patterns (just do it)
- Minor bug fixes (just do it)

---

## Quality Gates

No code is considered "done" until it passes all quality gates.

### Gate 1: Implementation Complete
- ✅ Feature works as designed
- ✅ Follows coding standards
- ✅ No compiler warnings
- ✅ BUILD_LEAD approves

### Gate 2: Tests Written
- ✅ Unit tests for business logic (80%+ coverage)
- ✅ Integration tests for API interactions
- ✅ All tests pass
- ✅ TEST_AGENT approves

### Gate 3: Code Review
- ✅ Clean code principles followed
- ✅ No code smells or technical debt
- ✅ Proper error handling
- ✅ REVIEW_AGENT approves

### Gate 4: Security Review
- ✅ No credential leakage
- ✅ Proper input validation
- ✅ Secure network communication
- ✅ SECURITY_COMPLIANCE approves

### Gate 5: Documentation
- ✅ Inline code documentation (doc comments)
- ✅ User-facing documentation updated
- ✅ Changelog entry added
- ✅ DOC_AGENT approves

### Gate 6: Design Review (if UI changes)
- ✅ Follows macOS Human Interface Guidelines
- ✅ Accessibility considerations
- ✅ Smooth animations and transitions
- ✅ UI_UX approves

---

## Reference Documents

### Primary References

**MUST READ FIRST**: Every agent must read these before taking any action:

1. **This Document (AGENTS.md)** - Project overview and coordination
2. **docs/DESIGN_DOCUMENT.md** - Complete technical specification
3. **Your Specific Agent File** - Your role and responsibilities

### Agent-Specific Files

Each agent has detailed instructions in `.agents/`:

- `.agents/BUILD_LEAD.md` - Lead developer instructions
- `.agents/SWIFT_EXPERT.md` - Swift specialist guidelines
- `.agents/API_INTEGRATION.md` - Docker API implementation
- `.agents/UI_UX.md` - Design and UX standards
- `.agents/SECURITY_COMPLIANCE.md` - Security requirements
- `.agents/TEST_AGENT.md` - Testing strategy
- `.agents/REVIEW_AGENT.md` - Code review checklist
- `.agents/DOC_AGENT.md` - Documentation standards

---

## Working Agreement

### All Agents Commit To:

1. **Read Before Acting**: Review AGENTS.md and docs/DESIGN_DOCUMENT.md before any work
2. **Follow Standards**: Adhere to coding standards and clean code principles
3. **Communicate**: Use `.agents/communications/` for coordination
4. **Respect Expertise**: Defer to specialist agents in their domains
5. **Security First**: Never compromise security for convenience
6. **Quality Over Speed**: Do it right, not fast
7. **Document Decisions**: Record important choices in `decisions.md`
8. **Test Everything**: No untested code
9. **User Focus**: Always consider the end user experience
10. **Continuous Improvement**: Learn from mistakes, iterate on processes

### Core Principles

**Single Responsibility**: Each agent focuses on their expertise  
**Collaboration**: Agents work together, not in silos  
**Transparency**: All decisions documented and visible  
**Quality**: No shortcuts, no technical debt  
**Security**: Non-negotiable, always enforced  

---

## Success Metrics

### Technical Metrics

| Metric | Target | Owner |
|--------|--------|-------|
| Test Coverage | ≥90% | TEST_AGENT |
| Memory Usage | <50MB | BUILD_LEAD |
| CPU (Idle) | <1% | BUILD_LEAD |
| Menu Latency | <100ms | BUILD_LEAD + UI_UX |
| Security Issues | 0 critical | SECURITY_COMPLIANCE |
| Documentation | 100% public APIs | DOC_AGENT |

### Quality Metrics

| Metric | Target | Owner |
|--------|--------|-------|
| Code Review Approval | 100% | REVIEW_AGENT |
| Clean Code Violations | 0 | REVIEW_AGENT |
| Compiler Warnings | 0 | BUILD_LEAD |
| SwiftLint Warnings | 0 | REVIEW_AGENT |

### User Experience Metrics

| Metric | Target | Owner |
|--------|--------|-------|
| Accessibility | VoiceOver support | UI_UX |
| Design Consistency | macOS HIG compliant | UI_UX |
| Error Messages | User-friendly | UI_UX + BUILD_LEAD |

---

## Getting Started

### For New Agents Joining the Project

1. **Read This Document** (AGENTS.md) - Understand the mission and your role
2. **Read docs/DESIGN_DOCUMENT.md** - Understand the technical architecture
3. **Read Your Agent File** - Understand your specific responsibilities
4. **Review Communications** - Check `.agents/communications/` for context
5. **Introduce Yourself** - Post in `daily-standup.md` that you're joining
6. **Start Small** - Pick up a well-defined task to get oriented

### For BUILD_LEAD Starting Work

1. ✅ Set up Swift package structure
2. ✅ Create basic project skeleton
3. ✅ Spawn SWIFT_EXPERT and API_INTEGRATION sub-agents
4. ✅ Start implementing Phase 1 features
5. ✅ Coordinate with other agents via communications folder

---

## Project Timeline

**Current Phase**: Phase 1 - MVP Foundation  
**Target Completion**: Week 2  
**Next Milestone**: Basic local Docker monitoring working

### Weekly Goals

**Week 1**: Core infrastructure
- Swift package setup
- Menu bar UI skeleton
- Docker API client (Unix socket)
- Basic container listing

**Week 2**: Container management
- Container stats retrieval
- Start/stop/restart actions
- Settings window
- Keychain integration

**Week 3-4**: Remote support and polish  
**Week 5-6**: Testing and release preparation

---

## Emergency Procedures

### Critical Security Issue Found

1. **STOP ALL WORK** - Security takes priority
2. **SECURITY_COMPLIANCE** assesses severity
3. **BUILD_LEAD** implements fix immediately
4. **TEST_AGENT** validates fix
5. **REVIEW_AGENT** expedited review
6. Document in `security-reviews.md`

### Blocker Encountered

1. Document in `open-questions.md`
2. Tag relevant agents for input
3. If urgent, BUILD_LEAD makes best judgment
4. Document decision in `decisions.md`
5. Continue with other work while waiting

### Agent Disagreement

1. Discuss in `open-questions.md`
2. Each agent presents their perspective
3. If security-related → SECURITY_COMPLIANCE decides
4. If design-related → UI_UX recommends, BUILD_LEAD decides
5. Otherwise → BUILD_LEAD decides
6. Document final decision in `decisions.md`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Jan 16, 2026 | Initial agent coordinator document |

---

## Contact & Support

**Project Repository**: [To be added]  
**Issue Tracker**: [To be added]  
**Communication Hub**: `.agents/communications/`

---

**Remember**: We're building something great together. Take pride in your work, help your fellow agents, and let's create a Docker monitoring tool that users love.

**Let's ship it! 🚀**