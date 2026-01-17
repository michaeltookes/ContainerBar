# DockerBar Project Orchestration Prompt

**Project**: DockerBar - macOS Menu Bar Docker Container Monitor  
**Phase**: Phase 1 - MVP Foundation  
**Date**: January 17, 2026

---

## Mission

Build DockerBar following the comprehensive design in `docs/DESIGN_DOCUMENT.md` using a coordinated team of specialized AI agents. Each agent has specific expertise and works together toward a production-ready application.

---

## Project Setup

**BEFORE STARTING**: All agents must read these documents in order:

1. **`/.claude/agents/AGENTS.md`** - Master coordinator with project overview
2. **`DESIGN_DOCUMENT.md`** - Complete technical specification (in repo root)
3. **Your specific agent file** - Your role and responsibilities

---

## Agent Team

### Primary Agents

**@BUILD_LEAD** - Lead Developer
- **File**: `/.claude/agents/BUILD_LEAD.md`
- **Role**: Owns implementation, spawns sub-agents, coordinates work
- **Authority**: Technical architecture decisions
- **Starts**: Immediately after reading requirements

**@UI_UX** - Design Expert
- **File**: `/.claude/agents/UI_UX.md`
- **Role**: Design review, UX guidance, accessibility
- **Authority**: Design decisions (can be overridden by SECURITY)
- **Reviews**: All UI implementations

**@SECURITY_COMPLIANCE** - Security Expert (VETO POWER)
- **File**: `/.claude/agents/SECURITY_COMPLIANCE.md`
- **Role**: Security review, vulnerability prevention
- **Authority**: **VETO POWER** on security decisions
- **Reviews**: All credential handling, network code, input validation

**@TEST_AGENT** - Quality Assurance
- **File**: `/.claude/agents/TEST_AGENT.md`
- **Role**: Testing, quality gates, coverage enforcement
- **Authority**: Can block releases if tests fail
- **Reviews**: Test coverage after every change

**@REVIEW_AGENT** - Code Review
- **File**: `/.claude/agents/REVIEW_AGENT.md`
- **Role**: Code review after EVERY change
- **Authority**: Code quality gates
- **Reviews**: All code for clean code principles

**@DOC_AGENT** - Documentation
- **File**: `/.claude/agents/DOC_AGENT.md`
- **Role**: Documentation after EVERY change
- **Authority**: Documentation completeness
- **Updates**: README, CHANGELOG, docs, code comments

### Sub-Agents (Spawned by BUILD_LEAD)

**@SWIFT_EXPERT** - Swift Specialist
- **File**: `/.claude/agents/SWIFT_EXPERT.md`
- **Spawned for**: Swift 6 concurrency, AppKit, SwiftUI patterns
- **Works with**: BUILD_LEAD

**@API_INTEGRATION** - Networking Specialist
- **File**: `/.claude/agents/API_INTEGRATION.md`
- **Spawned for**: Docker API client, networking, connection strategies
- **Works with**: BUILD_LEAD

---

## Development Workflow

### Phase 1: Week 1-2 - MVP Foundation

**Goal**: Basic menu bar app that can list and manage local Docker containers

#### Week 1: Core Infrastructure

**Day 1-2: Project Setup** (@BUILD_LEAD)

```
TASKS:
1. Read AGENTS.md and DESIGN_DOCUMENT.md
2. Create Swift package structure (Package.swift)
3. Set up DockerBar and DockerBarCore targets
4. Create basic README
5. Post completion in /.claude/agents/communications/daily-standup.md

QUALITY GATES:
- @REVIEW_AGENT: Review package structure
- @DOC_AGENT: Verify README is clear
```

**Day 3-4: Menu Bar UI** (@BUILD_LEAD + @SWIFT_EXPERT)

```
TASKS:
1. @BUILD_LEAD: Spawn @SWIFT_EXPERT for AppKit integration
2. @SWIFT_EXPERT: Create StatusItemController with menu bar icon
3. @SWIFT_EXPERT: Basic NSMenu with placeholder items
4. @UI_UX: Review menu bar icon design
5. @BUILD_LEAD: Integrate SWIFT_EXPERT's work

QUALITY GATES:
- @UI_UX: Approve icon design and menu layout
- @REVIEW_AGENT: Review code quality
- @TEST_AGENT: Unit tests for controller
- @DOC_AGENT: Document StatusItemController API
```

**Day 5: Docker API Foundation** (@BUILD_LEAD + @API_INTEGRATION)

```
TASKS:
1. @BUILD_LEAD: Spawn @API_INTEGRATION for Docker client
2. @API_INTEGRATION: Create DockerAPIClient protocol
3. @API_INTEGRATION: Implement Unix socket URLProtocol
4. @API_INTEGRATION: Create data models (DockerContainer, ContainerStats)
5. @SECURITY_COMPLIANCE: Review network security
6. @BUILD_LEAD: Integrate API_INTEGRATION's work

QUALITY GATES:
- @SECURITY_COMPLIANCE: Approve Unix socket security
- @TEST_AGENT: Integration tests with real Docker
- @REVIEW_AGENT: Review API client code
- @DOC_AGENT: Document API client methods
```

#### Week 2: Container Management

**Day 6-7: Container Listing** (@BUILD_LEAD + @SWIFT_EXPERT)

```
TASKS:
1. @SWIFT_EXPERT: Implement ContainerStore with @Observable
2. @BUILD_LEAD: Create ContainerFetcher service
3. @BUILD_LEAD: Display container list in menu
4. @UI_UX: Review container card design
5. @BUILD_LEAD: Implement container state display

QUALITY GATES:
- @TEST_AGENT: 90%+ coverage for ContainerStore
- @REVIEW_AGENT: Review @Observable implementation
- @UI_UX: Approve visual design
- @DOC_AGENT: Update CHANGELOG
```

**Day 8-9: Stats & Actions** (@BUILD_LEAD + @API_INTEGRATION)

```
TASKS:
1. @API_INTEGRATION: Implement stats streaming
2. @BUILD_LEAD: Integrate stats into UI
3. @BUILD_LEAD: Implement start/stop/restart actions
4. @UI_UX: Review metrics display
5. @SECURITY_COMPLIANCE: Review error handling

QUALITY GATES:
- @TEST_AGENT: Test all container actions
- @SECURITY_COMPLIANCE: No credential leaks in errors
- @REVIEW_AGENT: Review error handling
- @DOC_AGENT: Document container actions
```

**Day 10: Settings** (@BUILD_LEAD + @SWIFT_EXPERT)

```
TASKS:
1. @SWIFT_EXPERT: Create SettingsWindow
2. @BUILD_LEAD: Implement SettingsStore with persistence
3. @SECURITY_COMPLIANCE: Review Keychain integration
4. @UI_UX: Review settings UI
5. @BUILD_LEAD: Integrate settings

QUALITY GATES:
- @SECURITY_COMPLIANCE: Approve credential storage
- @TEST_AGENT: Test settings persistence
- @UI_UX: Approve window design
- @DOC_AGENT: Update user guide with settings
```

---

## Communication Protocol

### Daily Standups

**EVERY DAY**: Each active agent posts in `/.claude/agents/communications/daily-standup.md`

```markdown
## [Date] - @AGENT_NAME

**Completed**:
- Task 1
- Task 2

**In Progress**:
- Task 3

**Blockers**:
- Issue 1

**Next Up**:
- Task 4
```

### Decision Making

**WHEN NEEDED**: Post in `/.claude/agents/communications/decisions.md`

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

### Questions

**WHEN STUCK**: Post in `/.claude/agents/communications/open-questions.md`

```markdown
## [Date] - Question: [Title]

@TAGGED_AGENT - Description

**Status**: Open / Resolved
```

### Reviews

**AFTER EVERY CHANGE**:
- @REVIEW_AGENT: Posts review in communications/
- @SECURITY_COMPLIANCE: Posts security review (if relevant)
- @UI_UX: Posts design feedback (if UI changed)

---

## Quality Gates (Must Pass Before "Done")

### Gate 1: Implementation (@BUILD_LEAD)
- ✅ Feature works as designed
- ✅ Follows coding standards
- ✅ No compiler warnings

### Gate 2: Testing (@TEST_AGENT)
- ✅ Unit tests written (80%+ coverage)
- ✅ All tests pass
- ✅ Edge cases covered

### Gate 3: Code Review (@REVIEW_AGENT)
- ✅ Clean code principles followed
- ✅ No code smells
- ✅ Proper error handling

### Gate 4: Security (@SECURITY_COMPLIANCE)
- ✅ No credential leaks
- ✅ Input validation present
- ✅ Secure network communication

### Gate 5: Documentation (@DOC_AGENT)
- ✅ Code comments on public APIs
- ✅ CHANGELOG updated
- ✅ User docs updated (if needed)

### Gate 6: Design (@UI_UX - if UI changes)
- ✅ Follows macOS HIG
- ✅ Accessible
- ✅ Visually polished

**NO CODE IS "DONE" UNTIL ALL GATES PASS**

---

## Success Metrics

### Phase 1 Completion Criteria

- ✅ Can connect to local Docker daemon
- ✅ Can list all containers (running and stopped)
- ✅ Can view container stats (CPU, memory)
- ✅ Can start/stop/restart containers
- ✅ Settings window for configuration
- ✅ Auto-refresh with configurable interval
- ✅ 90%+ test coverage
- ✅ Zero compiler warnings
- ✅ Zero critical security issues
- ✅ Complete documentation

### Performance Targets

- Menu opens in <100ms
- Stats update in <1 second
- Memory usage <50MB
- CPU usage <1% when idle

---

## Getting Started

### For BUILD_LEAD (Start Here!)

You are the primary agent who kicks off the project. Here's your immediate action plan:

**Step 1**: Read the requirements
```
1. Read /.claude/agents/AGENTS.md (project overview)
2. Read DESIGN_DOCUMENT.md (complete spec - in repo root)
3. Read /.claude/agents/BUILD_LEAD.md (your role)
```

**Step 2**: Set up the project
```
1. Create Swift package structure
2. Set up targets (DockerBar, DockerBarCore, Tests)
3. Configure Package.swift with dependencies
4. Create basic README
```

**Step 3**: Post your first standup
```markdown
## [Date] - @BUILD_LEAD

**Completed**:
- ✅ Read all requirements
- ✅ Created Swift package structure
- ✅ Set up DockerBar and DockerBarCore targets

**In Progress**:
- 🔄 Setting up basic project skeleton

**Next Up**:
- Spawn @SWIFT_EXPERT for menu bar implementation
- Spawn @API_INTEGRATION for Docker client
```

**Step 4**: Start building (follow Week 1 schedule above)

### For Review Agents

**@REVIEW_AGENT**: 
- Monitor BUILD_LEAD's daily standups
- Review every code change
- Post feedback promptly

**@SECURITY_COMPLIANCE**:
- Review all network code, credential handling
- Use your VETO POWER when needed
- Post security reviews

**@TEST_AGENT**:
- Ensure tests exist for every feature
- Monitor coverage
- Block merge if coverage <80%

**@UI_UX**:
- Review all UI implementations
- Provide design feedback
- Ensure accessibility

**@DOC_AGENT**:
- Document after EVERY change
- Keep CHANGELOG updated
- Ensure 100% API documentation

---

## Example Day 1 Orchestration

Here's what happens on Day 1:

**Morning**:
```
@BUILD_LEAD reads requirements → Creates package structure → Posts standup

@DOC_AGENT reviews README → Posts feedback

@REVIEW_AGENT reviews Package.swift → Approves structure
```

**Afternoon**:
```
@BUILD_LEAD creates basic AppDelegate → Posts in standup

@REVIEW_AGENT reviews code → Requests changes (missing doc comments)

@BUILD_LEAD adds doc comments → Re-submits

@DOC_AGENT updates CHANGELOG → Posts completion

@REVIEW_AGENT approves → @BUILD_LEAD moves to next task
```

**End of Day**:
```
All agents post daily standups with progress
```

---

## Important Reminders

### For All Agents

1. **Read First**: AGENTS.md, DESIGN_DOCUMENT.md, your agent file
2. **Communicate**: Use /.claude/agents/communications/ for all coordination
3. **Quality First**: Don't skip quality gates
4. **Security Always**: Never compromise security
5. **Document Everything**: After every change
6. **Collaborate**: Help each other succeed

### For BUILD_LEAD

- You drive the project forward
- Spawn sub-agents when needed
- Coordinate all work
- Trust specialist agents in their domains
- Don't skip quality gates

### For Review Agents

- Review promptly (don't block progress)
- Be constructive with feedback
- Enforce standards consistently
- Help BUILD_LEAD learn and improve

---

## Emergency Procedures

### Critical Security Issue
1. @SECURITY_COMPLIANCE identifies issue
2. All work stops on that component
3. @BUILD_LEAD fixes immediately
4. @SECURITY_COMPLIANCE re-reviews
5. Work resumes

### Blocked on Decision
1. Post in open-questions.md
2. Tag relevant agents
3. If urgent, @BUILD_LEAD makes call
4. Document in decisions.md

### Agent Disagreement
1. Discuss in open-questions.md
2. If security-related → @SECURITY_COMPLIANCE decides
3. If design-related → @UI_UX recommends, @BUILD_LEAD decides
4. Otherwise → @BUILD_LEAD decides
5. Document in decisions.md

---

## Let's Build DockerBar! 🚀

**@BUILD_LEAD**: You're up! Read the requirements and start with Day 1 tasks.

**All other agents**: Monitor communications folder and jump in when your expertise is needed.

**Remember**: We're building something great together. Quality over speed. Communication is key. Let's ship it!

---

## Quick Commands Reference

```bash
# Build
swift build

# Run tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Lint
swiftlint

# Format
swiftformat .

# Run app
swift run
```

---

**Project Start Date**: January 17, 2026  
**Target MVP Completion**: February 2, 2026 (2 weeks)  
**Current Phase**: Phase 1 - MVP Foundation  

**Let's go! 🐳**