# Implementation Plan: remove_code_fences_20260310

## Phase 1: Test Infrastructure and Initial Failing Tests [checkpoint: 65f653b]

- [x] Task: Create test file `gptel-magit-tests.el` [19eb629]
    - [ ] Initialize the test file with necessary requires (`ert`, `gptel-magit`).
- [x] Task: Implement failing tests for triple backtick removal [21ba876]
    - [ ] Write a test case for triple backtick code fences (` ``` `) wrapping the entire message.
    - [ ] Write a test case for messages with leading/trailing whitespace around triple fences.
    - [ ] Write a test case that includes single backticks (`` ` ``) *inside* the message, ensuring they are preserved.
    - [ ] **CRITICAL:** Run tests and confirm they fail.
- [x] Task: Conductor - User Manual Verification 'Phase 1: Test Infrastructure and Initial Failing Tests' (Protocol in workflow.md) [65f653b]

## Phase 2: Implementation and Verification

- [x] Task: Refine `gptel-magit--format-commit-message` to strip triple fences and whitespace [10565f4]
    - [ ] Implement logic to remove only triple backtick fences.
    - [ ] Implement logic to trim leading/trailing whitespace.
    - [ ] Ensure that single backticks are *not* removed.
    - [ ] Ensure the existing filling logic is preserved and correctly applied to the cleaned message.
- [x] Task: Verify implementation with tests [10565f4]
    - [ ] Run the ERT test suite and ensure all tests in `gptel-magit-tests.el` pass.
- [x] Task: Quality Gate Check [10565f4]
    - [ ] Verify test coverage for the new logic.
    - [ ] Run `package-lint` on `gptel-magit.el` (if available).
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Implementation and Verification' (Protocol in workflow.md)
