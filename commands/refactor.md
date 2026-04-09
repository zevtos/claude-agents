---
description: "Safe refactoring workflow: detect smells → plan → characterization tests → refactor → verify. Ensures refactors don't break existing behavior."
argument-hint: <what to refactor and why, or area of code>
---

You are orchestrating a safe refactoring. The #1 rule: refactoring must not change external behavior. Every step must preserve the existing test suite passing.

## Context
@CLAUDE.md

## Refactoring Goal
$ARGUMENTS

## Pipeline

### Step 1: Detect — MANDATORY
You MUST use the Agent tool with `subagent_type: "refactorer"` to run the refactorer agent. Do NOT skip this step.

Prompt for the refactorer agent:
"Analyze this codebase for refactoring opportunities. Focus area: $ARGUMENTS

Scan for:
1. Code duplication and clone groups
2. Code smells (god functions, feature envy, primitive obsession, unnecessary complexity)
3. Dead code and unreachable branches
4. Single source of truth violations (constants/config defined in multiple places)
5. Test suite problems (meaningless tests, duplicate patterns, missing factories)
6. Scalability issues (adding a new type requires changes in 5+ files)

Produce a prioritized findings report with specific file:line locations and fixes."

Wait for the refactorer agent to complete. Present its findings to the user.

Ask: "Found [count] findings ([high/medium/low breakdown]). This is a [RISK] refactor. Proceed with fixes?"

### Step 2: Safety Net (Tester Agent — if needed)
If test coverage is insufficient for the refactored code, run the `tester` agent:
"Write characterization tests for the following code BEFORE refactoring:
[list files/functions being refactored from refactorer findings]
These tests must capture the CURRENT behavior exactly — they serve as a safety net.
Focus on: all public API surfaces, edge cases, error paths."

Run the characterization tests to verify they pass.

### Step 3: Architecture Review (Architect Agent — if structural)
If the refactorer found structural issues (module boundaries, API contracts, decomposition), run the `architect` agent:
"Review this refactoring plan:
Goal: $ARGUMENTS
Refactorer findings: [paste structural findings]

Evaluate:
- Is this the right decomposition?
- Are the new boundaries clean?
- Does this create better or worse coupling?
- Any migration concerns?"

### Step 4: Implement
Apply refactoring findings in priority order (high impact first), in small steps:
1. Make one change at a time
2. Run tests after EACH change
3. If tests fail, revert the last change and investigate
4. Keep commits atomic — each commit is a standalone refactoring step that passes all tests
5. Follow the refactorer's specific fix instructions for each finding

### Step 5: Review (Reviewer Agent)
Run the `reviewer` agent:
"Review this refactoring of: $ARGUMENTS
Key verification:
- External behavior is UNCHANGED (no new features, no bug fixes mixed in)
- All existing tests still pass
- Code quality improved (the refactoring actually helps)
- No accidental API changes
- No accidental behavior changes hiding in the diff"

Fix any findings.

### Step 6: Verify
1. Run the FULL test suite (not just tests for changed files)
2. If the project has integration/e2e tests, run those too
3. Verify no test was modified to "make it pass" with new behavior

Present:
- What changed (structural overview)
- What did NOT change (externally visible behavior)
- Test results (all passing)
- Commits ready (one per refactoring step, conventional format: `refactor: ...`)
