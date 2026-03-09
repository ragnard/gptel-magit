# Implementation Plan: remove_code_fences_20260310

## Phase 1: Test Infrastructure and Initial Failing Tests

- [ ] Task: Create test file `gptel-magit-tests.el`
    - [ ] Initialize the test file with necessary requires (`ert`, `gptel-magit`).
- [ ] Task: Implement failing tests for code fence removal
    - [ ] Write a test case for triple backtick code fences (` ``` `).
    - [ ] Write a test case for single backtick code fences (`` ` ``).
    - [ ] Write a test case for messages with leading/trailing whitespace.
    - [ ] Write a test case for messages that combine fences and whitespace.
    - [ ] **CRITICAL:** Run tests and confirm they fail.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Test Infrastructure and Initial Failing Tests' (Protocol in workflow.md)

## Phase 2: Implementation and Verification

- [ ] Task: Refine `gptel-magit--format-commit-message` to strip fences and whitespace
    - [ ] Implement logic to remove triple backtick fences.
    - [ ] Implement logic to remove single backtick fences.
    - [ ] Implement logic to trim leading/trailing whitespace.
    - [ ] Ensure the existing filling logic is preserved and correctly applied to the cleaned message.
- [ ] Task: Verify implementation with tests
    - [ ] Run the ERT test suite and ensure all tests in `gptel-magit-tests.el` pass.
- [ ] Task: Quality Gate Check
    - [ ] Verify test coverage for the new logic.
    - [ ] Run `package-lint` on `gptel-magit.el` (if available).
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Implementation and Verification' (Protocol in workflow.md)
