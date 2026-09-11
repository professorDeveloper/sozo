# KAIZOKU — ECC INTEGRATION & WORKFLOW SPECIFICATION

> **ECC Source Authority:** Local directory `d:/sandcat2.0/.agents/`  
> **Harness:** Antigravity IDE (Google DeepMind Advanced Agentic Coding)  
> **Install Manifest:** `.agents/ecc-install-state.json` (Target: `antigravity-project`, Commit: `f864035`)

---

## 1. ANTIGRAVITY DISCOVERY & LOADING MECHANISMS

The Antigravity system automatically discovers and registers customizations placed inside `.agents/` at the root of the active workspace (`d:/sandcat2.0/`):

### 1.1 Automatically Loaded Components
* **Path-Matched Rules (`.agents/rules/`):**
  Antigravity automatically parses YAML frontmatter in rule markdown files and injects them into the prompt whenever active files or targeted edits match the glob patterns:
  - `dart-coding-style.md`: Triggers on `**/*.dart`, `**/pubspec.yaml`, `**/analysis_options.yaml`. Enforces `dart format`, 80-char width, immutability (`final`/`const`), null safety, Dart 3 sealed types and exhaustive pattern matching.
  - `dart-patterns.md`: Triggers on Dart files. Enforces Clean Architecture, BLoC pattern, repository contracts, and separation of UI from data access.
  - `dart-security.md`: Triggers on Dart files. Enforces secure storage for credentials, input sanitization, safe deserialization, and prevention of secret leakage.
  - `dart-testing.md`: Triggers on Dart test files. Enforces Arrange-Act-Assert structure, mock isolation, and test naming conventions.
  - `common-*.md`: Coding style, performance, security, and git standards applied across all files.

### 1.2 On-Demand Skills (`.agents/skills/`)
Skills are specialized instruction sets located in `.agents/skills/<skill_name>/SKILL.md`. In Antigravity, they are activated:
- When a task requires specialized domain knowledge (e.g., `tdd-workflow`, `security-review`, `browser-qa`).
- When explicitly read by the agent using `view_file` before undertaking complex multi-step work.
- In Kaizoku, critical skills are:
  - `tdd-workflow`: Drives the RED -> GREEN -> REFACTOR cycle.
  - `flutter-patterns` / `frontend-patterns`: Drives component composition and widget tree hygiene.
  - `security-review`: Gating before merge/release.
  - `verification-loop`: Comprehensive pre-completion validation.

### 1.3 Workflows / Slash Commands (`.agents/workflows/`)
Workflows are executable markdown recipes exposed to the user and agent via slash commands:
- `/flutter-build`: Automated Dart analyzer and build error diagnosis and resolution. Invokes the `dart-build-resolver` agent.
- `/flutter-review`: Deep Flutter/Dart code review checking idiomatic patterns, widget best practices, state management, render performance, and accessibility. Invokes the `flutter-reviewer` agent.
- `/flutter-test`: Runs Flutter/Dart tests, reports failures, and guides surgical fixes.
- `/plan`: Requirements analysis, risk assessment, and step-by-step implementation plan with user confirmation gating.
- `/security-scan`: Runs AgentShield and security audit over agent, permission, secret, and code surfaces.
- `/checkpoint`: Creates and verifies workflow checkpoints after verification gates pass.

### 1.4 Specialized Agents (`.agents/agents/`)
Specialized system prompts defining expert personas:
- `flutter-reviewer.md`: Strict code reviewer evaluating widget rebuild scopes, null-safety, memory leaks, and Dart 3 idioms.
- `dart-build-resolver.md`: Surgical build and compiler error resolver.
- `architect.md`: System boundary and dependency enforcement.
- `security-reviewer.md`: Vulnerability scanner checking secrets, injection, and local storage exposure.
- `tdd-guide.md`: TDD enforcement mentor.

---

## 2. STANDARD WORKFLOW EXECUTION PROTOCOLS

### 2.1 Planning Protocol
1. **Requirements Gathering:** Deep inspection of existing code, API payloads, and state models.
2. **Implementation Plan Artifact:** Generated into `<artifacts>/implementation_plan.md`.
3. **User Approval Gate:** STOP and wait for explicit confirmation from user before touching production source code.

### 2.2 Test-Driven Development (TDD) Protocol
1. **RED:** Write unit or widget test asserting desired behavior. Verify test fails for the right reason.
2. **GREEN:** Write minimal production code necessary to satisfy the test. Verify test passes.
3. **REFACTOR:** Clean up implementation, optimize performance, ensure adherence to `dart-coding-style.md`, while keeping tests green.
4. **REVIEW:** Run static analysis and lint checks.

### 2.3 Code Review Protocol
1. Invoked on any non-trivial pull request or phase completion.
2. Inspects:
   - Immutability and `const` constructor usage.
   - Elimination of `BuildContext` leaks across async gaps (`mounted` guards).
   - Widget tree rebuild minimization (selective `BlocBuilder.buildWhen` / `ValueListenableBuilder`).
   - Clean architecture boundary preservation (zero UI imports in Domain).

### 2.4 Security Review Protocol
1. Secret Audit: No API keys, passwords, or private tokens hard-coded in source.
2. Local Storage: Sensitive data (PIN hash/salt) restricted to `flutter_secure_storage`.
3. Network Transport: TLS enforcement, secure cookie storage, and safe URL parsing.
4. Platform Channels: Validated input types on MethodChannel handlers to prevent native crashes.

### 2.5 Fresh-Context Review Protocol
To eliminate conversational bias and hallucination drift after extensive editing sessions:
1. Isolate the diff / changeset.
2. Formulate an explicit review prompt providing only the diff and specifications.
3. Run an independent evaluation pass (`agent-self-evaluation` or `santa-method`) scoring on Accuracy, Completeness, Actionability, and Zero Regressions.
