# Implementation Plan: remove_code_fences_20260310

## Phase 1: Test Infrastructure and Initial Failing Tests

- [x] Task: Create test file `gptel-magit-tests.el` [19eb629]
    - [ ] Initialize the test file with necessary requires (`ert`, `gptel-magit`).
- [x] Task: Implement failing tests for triple backtick removal [21ba876]
    - [ ] Write a test case for triple backtick code fences (` ``` `) wrapping the entire message.
    - [ ] Write a test case for messages with leading/trailing whitespace around triple fences.
    - [ ] Write a test case that includes single backticks (`` ` ``) *inside* the message, ensuring they are preserved.
    - [ ] **CRITICAL:** Run tests and confirm they fail.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Test Infrastructure and Initial Failing Tests' (Protocol in workflow.md)

## Phase 2: Implementation and Verification

- [ ] Task: Refine `gptel-magit--format-commit-message` to strip triple fences and whitespace
    - [ ] Implement logic to remove only triple backtick fences.
    - [ ] Implement logic to trim leading/trailing whitespace.
    - [ ] Ensure that single backticks are *not* removed.
    - [ ] Ensure the existing filling logic is preserved and correctly applied to the cleaned message.
- [ ] Task: Verify implementation with tests
    - [ ] Run the ERT test suite and ensure all tests in `gptel-magit-tests.el` pass.
- [ ] Task: Quality Gate Check
    - [ ] Verify test coverage for the new logic.
    - [ ] Run `package-lint` on `gptel-magit.el` (if available).
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Implementation and Verification' (Protocol in workflow.md)
