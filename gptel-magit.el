;;; gptel-magit.el --- Generate commit messages for magit using gptel -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Authors
;; SPDX-License-Identifier: Apache-2.0

;; Author: Ragnar Dahlén <r.dahlen@gmail.com>
;; Version: 1.0
;; Package-Requires: ((emacs "28.1") (magit "4.0") (gptel "0.9.8"))
;; Keywords: vc, convenience
;; URL: https://github.com/ragnard/gptel-magit

;;; Commentary:

;; This package uses the gptel library to add LLM integration into
;; magit. Currently, it adds functionality for generating commit
;; messages.

;;; Code:

(require 'gptel)
(require 'magit)

(defconst gptel-magit-prompt-zed
  "You are an expert at writing Git commits. Your job is to write a short clear commit message that summarizes the changes.

If you can accurately express the change in just the subject line, don't include anything in the message body. Only use the body when it is providing *useful* information.

Don't repeat information from the subject line in the message body.

Only return the commit message in your response. Do not include any additional meta-commentary about the task. Do not include the raw diff output in the commit message.

Follow good Git style:

- Separate the subject from the body with a blank line
- Try to limit the subject line to 50 characters
- Capitalize the subject line
- Do not end the subject line with any punctuation
- Use the imperative mood in the subject line
- Wrap the body at 68 characters
- Keep the body short and concise (omit it entirely if not useful)"
  "A prompt adapted from Zed (https://github.com/zed-industries/zed/blob/main/crates/git_ui/src/commit_message_prompt.txt).")

(defconst gptel-magit-prompt-conventional-commits
  "You are an expert at writing Git commits. Your job is to write a short clear commit message that summarizes the changes.

The commit message should be structured as follows:

    <type>(<optional scope>): <description>

    [optional body]

- Commits MUST be prefixed with a type, which consists of one of the followings words: build, chore, ci, docs, feat, fix, perf, refactor, style, test
- The type feat MUST be used when a commit adds a new feature
- The type fix MUST be used when a commit represents a bug fix
- An optional scope MAY be provided after a type. A scope is a phrase describing a section of the codebase enclosed in parenthesis, e.g., fix(parser):
- A description MUST immediately follow the type/scope prefix. The description is a short description of the code changes, e.g., fix: array parsing issue when multiple spaces were contained in string.
- Try to limit the whole subject line to 60 characters
- Capitalize the subject line
- Do not end the subject line with any punctuation
- A longer commit body MAY be provided after the short description, providing additional contextual information about the code changes. The body MUST begin one blank line after the description.
- Use the imperative mood in the subject line
- Keep the body short and concise (omit it entirely if not useful)"
  "A prompt adapted from Conventional Commits (https://www.conventionalcommits.org/en/v1.0.0/).")

(defcustom gptel-magit-body-length nil
  "Maximum character length for commit message body lines.
If nil, no body length constraint is mentioned in the prompt."
  :type '(choice (const :tag "No constraint" nil)
                 (integer :tag "Character limit"))
  :group 'gptel-magit)

(defcustom gptel-magit-commit-prompt
  gptel-magit-prompt-conventional-commits
  "The prompt to use for generating a commit message.
The prompt should consider that the input will be a diff of all
staged changes."
  :type 'string
  :group 'gptel-magit)

(defcustom gptel-magit-diff-explain-prompt
  "You are an expert at understanding and explaining code changes by reading diff output. Your job is to write a short clear summary explanation of the changes the changes. Answer in Markdown format."
  "The prompt to use for explaining diff changes.
The prompt should consider that the input will be a diff some changes."
  :type 'string
  :group 'gptel-magit)

(custom-declare-variable
 'gptel-magit-model nil
 "The gptel model to use, defaults to `gptel-model` if nil.

See `gptel-model` for documentation.

If set to a model that uses a different backend than
`gptel-backend`, also requires `gptel-magit-backend' to be set to
the correct backend."
 :type (get 'gptel-model 'custom-type)
 :group 'gptel-magit)

(custom-declare-variable
 'gptel-magit-backend nil
 "The gptel backend to use, defaults to `gptel-backend` if nil.

See `gptel-backend` for documentation."
 :type (get 'gptel-backend 'custom-type)
 :group 'gptel-magit)


(defvar gptel-magit-rationale-buffer "*gptel-magit Rationale*"
  "Buffer name for entering rationale for commit message generation.")

(defvar gptel-magit--current-commit-buffer nil
  "Buffer where commit message is being generated.")

(defun gptel-magit--format-commit-message (message)
  "Format commit message MESSAGE nicely."
  (with-temp-buffer
    (insert message)
    (text-mode)
    (setq fill-column git-commit-summary-max-length)
    (goto-char (point-min))
    (let ((end-of-first-line (progn (end-of-line) (point))))
      (fill-region (point-min) end-of-first-line))
    (buffer-string)))

(defun gptel-magit--get-commit-prompt ()
  "Get the commit prompt, potentially modified based on configuration."
  (cond
   ;; If using conventional commits and body length is set, append the body length line
   ((and (string= gptel-magit-commit-prompt gptel-magit-prompt-conventional-commits)
         gptel-magit-body-length)
    (concat gptel-magit-prompt-conventional-commits
            (format "\n- Try to limit the body line number to %d characters" gptel-magit-body-length)))
   ;; For all other cases, use the prompt as-is
   (t gptel-magit-commit-prompt)))

(defun gptel-magit--request (&rest args)
  "Call `gptel-request` with ARGS.

Respects configured model/backend options."
  (declare (indent 1))
  (let* ((gptel-backend (or gptel-magit-backend gptel-backend))
         (gptel-model (or gptel-magit-model gptel-model)))
    (apply #'gptel-request args)))

(defun gptel-magit--generate (callback &optional rationale)
  "Generate a commit message for current magit repo.
Invokes CALLBACK with the generated message when done.
Optional RATIONALE provides context for why the change was made."
  (let* ((diff (magit-git-output "diff" "--cached"))
         (prompt (if (and rationale (not (string-empty-p rationale)))
                     (format "Why this change was made: %s\n\nCode changes:\n%s" rationale diff)
                   diff)))
    (gptel-magit--request prompt
      :system (gptel-magit--get-commit-prompt)
      :context nil
      :callback (lambda (response info)
                  (cond
                   ((stringp response)
                    (let ((msg (gptel-magit--format-commit-message response)))
                      (funcall callback msg)))
                   ((and (consp response) (eq (car response) 'reasoning))
                    nil) ; silently ignore reasoning traces
                   ((null response)
                    (message "gptel-magit: Empty response from LLM (%s)"
                             (or (plist-get info :status) "unknown status"))))))))

(defun gptel-magit-generate-message ()
  "Generate a commit message when in the git commit buffer."
  (interactive)
  (unless (magit-commit-message-buffer)
    (user-error "No commit in progress"))
  (gptel-magit--generate (lambda (message)
                           (with-current-buffer (magit-commit-message-buffer)
                             (save-excursion
                               (goto-char (point-min))
                               (insert message)))))
  (message "magit-gptel: Generating commit message..."))

(defun gptel-magit-commit-generate (&optional args)
  "Create a new commit with a generated commit message.
Uses ARGS from transient mode."
  (interactive (list (magit-commit-arguments)))
  (gptel-magit--generate
   (lambda (message)
     (magit-commit-create (append args `("--message" ,message "--edit")))))
  (message "magit-gptel: Generating commit..."))

(defun gptel-magit--show-diff-explain (text)
  "Popup a buffer with diff explanation TEXT."
  (let ((buffer-name "*gptel-magit diff-explain*"))
    (when-let ((existing-buffer (get-buffer buffer-name)))
      (kill-buffer existing-buffer))
    (let ((buffer (get-buffer-create buffer-name)))
      (with-current-buffer buffer
        (insert text)
        (setq fill-column 72)
        (fill-region (point-min) (point-max))
        (markdown-view-mode)
        (goto-char (point-min)))
      (pop-to-buffer buffer))))

(defun gptel-magit--do-diff-request (diff)
  "Send request for an explanation of DIFF."
  (gptel-magit--request diff
    :system gptel-magit-diff-explain-prompt
    :context nil
    :callback (lambda (response info)
                (cond
                 ((stringp response)
                  (gptel-magit--show-diff-explain response))
                 ((and (consp response) (eq (car response) 'reasoning))
                  nil)
                 ((null response)
                  (message "gptel-magit: Empty response from LLM (%s)"
                           (or (plist-get info :status) "unknown status"))))))
  (message "magit-gptel: Explaining diff..."))

(defun gptel-magit-diff-explain ()
  "Ask for an explanation of diff at current section."
  (interactive)
  (when-let* ((section (magit-current-section))
              (start (oref section content))
              (end (oref section end))
              (content (buffer-substring start end)))
    (gptel-magit--do-diff-request content)))

(define-derived-mode gptel-magit-rationale-mode text-mode "gptel-magit-Rationale"
  "Mode for entering commit rationale before generating commit message."
  (local-set-key (kbd "C-c C-c") #'gptel-magit--submit-rationale)
  (local-set-key (kbd "C-c C-k") #'gptel-magit--cancel-rationale))

(defun gptel-magit--setup-rationale-buffer ()
  "Setup the rationale buffer with proper guidance."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert ";;; WHY are you making these changes? (optional)\n")
    (insert ";;; Press C-c C-c to generate commit message, C-c C-k to cancel\n")
    (insert ";;; Leave empty to generate without rationale\n")
    (insert ";;; ────────────────────────────────────────────────────────\n")
    (add-text-properties (point-min) (point)
                         '(face font-lock-comment-face read-only t))
    (insert "\n")
    (goto-char (point-max))))

(defun gptel-magit--submit-rationale ()
  "Submit the rationale buffer content and proceed with commit generation."
  (interactive)
  (let ((rationale (string-trim
                    (buffer-substring-no-properties
                     (save-excursion
                       (goto-char (point-min))
                       (while (and (not (eobp))
                                   (get-text-property (point) 'read-only))
                         (forward-char))
                       (point))
                     (point-max)))))
    (quit-window t)
    (gptel-magit--generate
     (lambda (message)
       (with-current-buffer gptel-magit--current-commit-buffer
         (save-excursion
           (goto-char (point-min))
           (insert message))))
     rationale)
    (message "magit-gptel: Generating commit message with rationale...")))

(defun gptel-magit--cancel-rationale ()
  "Cancel rationale input and abort commit generation."
  (interactive)
  (quit-window t)
  (message "Commit generation canceled."))

(defun gptel-magit-generate-message-with-rationale ()
  "Generate a commit message with rationale when in the git commit buffer."
  (interactive)
  (unless (magit-commit-message-buffer)
    (user-error "No commit in progress"))
  (setq gptel-magit--current-commit-buffer (magit-commit-message-buffer))
  (let ((buffer (get-buffer-create gptel-magit-rationale-buffer)))
    (with-current-buffer buffer
      (gptel-magit-rationale-mode)
      (gptel-magit--setup-rationale-buffer))
    (pop-to-buffer buffer)))

(defun gptel-magit-commit-generate-with-rationale (&optional args)
  "Create a new commit with a generated commit message with rationale.
Uses ARGS from transient mode."
  (interactive (list (magit-commit-arguments)))
  (setq gptel-magit--current-commit-buffer nil)
  (let ((buffer (get-buffer-create gptel-magit-rationale-buffer)))
    (with-current-buffer buffer
      (gptel-magit-rationale-mode)
      (gptel-magit--setup-rationale-buffer)
      (local-set-key (kbd "C-c C-c")
                     (lambda ()
                       (interactive)
                       (let ((rationale (string-trim
                                         (buffer-substring-no-properties
                                          (save-excursion
                                            (goto-char (point-min))
                                            (while (and (not (eobp))
                                                        (get-text-property (point) 'read-only))
                                              (forward-char))
                                            (point))
                                          (point-max)))))
                         (quit-window t)
                         (gptel-magit--generate
                          (lambda (message)
                            (magit-commit-create (append args `("--message" ,message "--edit"))))
                          rationale)
                         (message "magit-gptel: Generating commit with rationale...")))))
    (pop-to-buffer buffer)))

;;;###autoload
(defun gptel-magit-install ()
  "Install gptel-magit functionality."
  (define-key git-commit-mode-map (kbd "M-g") 'gptel-magit-generate-message)
  (define-key git-commit-mode-map (kbd "M-r") 'gptel-magit-generate-message-with-rationale)
  (transient-append-suffix 'magit-commit #'magit-commit-create
    '("g" "Generate commit" gptel-magit-commit-generate))
  (transient-append-suffix 'magit-commit #'gptel-magit-commit-generate
    '("r" "Generate with rationale" gptel-magit-commit-generate-with-rationale))
  (transient-append-suffix 'magit-diff #'magit-stash-show
    '("x" "Explain" gptel-magit-diff-explain)))

(provide 'gptel-magit)
;;; gptel-magit.el ends here
