;;; gptel-magit-tests.el --- Tests for gptel-magit -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Authors
;; SPDX-License-Identifier: Apache-2.0

;;; Code:

(require 'ert)
(require 'git-commit)
(require 'gptel-magit)

(ert-deftest gptel-magit-format-commit-message-test-fences ()
  "Test triple backtick removal from commit messages."
  (let ((git-commit-summary-max-length 50))
    (should (string= "feat(test): message"
                     (gptel-magit--format-commit-message "``` feat(test): message ```")))
    (should (string= "feat(test): message"
                     (gptel-magit--format-commit-message "```\nfeat(test): message\n```")))
    (should (string= "feat(test): message"
                     (gptel-magit--format-commit-message "  ```\n  feat(test): message\n  ```  ")))))

(ert-deftest gptel-magit-format-commit-message-test-single-backticks ()
  "Test that single backticks are preserved."
  (let ((git-commit-summary-max-length 50))
    (should (string= "feat(test): add `func`"
                     (gptel-magit--format-commit-message "feat(test): add `func`")))
    (should (string= "feat(test): add `func`"
                     (gptel-magit--format-commit-message "``` feat(test): add `func` ```")))))

(provide 'gptel-magit-tests)
;;; gptel-magit-tests.el ends here
