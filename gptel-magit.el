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

(defcustom gptel-magit-commit-styles-alist
  '(("GNU Style" . "You are an expert at writing Git commits in the GNU/Emacs ChangeLog style.
Your job is to write a detailed, clear commit message that summarizes the changes with technical precision.

### TRIVIAL CHANGES RULE:
- If the change is trivial (e.g., fixing a typo, adjusting indentation, or purely cosmetic), START the commit message with a semicolon (;).
- For trivial changes, provide only a concise one-line summary. 
- Example: \"; gptel: Fix typo in docstring\"
- DO NOT use the bulleted ChangeLog format for trivial changes.

### FUNCTIONAL CHANGES RULE:

For all non-trivial changes, use the following structure:

    <component>: <short summary>

    * <file-name> (<function-name>): <detailed description of changes>.
    [optional additional entries for other files/functions]

- MANDATORY: Use asterisk (*) ONLY at the start of a file entry. 
- MANDATORY: Indent continuation lines. NEVER start a line with an asterisk unless it's a NEW file/function.
- DO NOT repeat the filename at the end of paragraphs.
- The first line (subject) MUST start with the component or file prefix followed by a colon.
- The subject line MUST be in the imperative mood and max 66 characters.
- DO NOT use conventional commit prefixes like fix: or feat:.
- The body MUST use the ChangeLog format: asterisk, filename, function name in parentheses, and the \"why/how\".
- FORMATTING: Indent continuation lines and do not repeat the filename at the end of the description.
- If multiple functions or files changed, provide a separate bullet point for each.
- Do not end the subject line with any punctuation.
- Use a professional, technical, and descriptive tone.")
    ;; "Prompt string for GNU-style commit messages with trivial change support."
    ;;A prompt adapted from Zed (https://github.com/zed-industries/zed/blob/main/crates/git_ui/src/commit_message_prompt.).
    ("ZED Style" . "You are an expert at writing Git commits. Your job is to write a short clear commit message that summarizes the changes.

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
- Keep the body short and concise (omit it entirely if not useful)")
    ;;A prompt adapted from Conventional Commits (https://www.conventionalcommits.org/en/v1.0.0/).
    ("Conventional Commits" . "You are an expert at writing Git commits. Your job is to write a short clear commit message that summarizes the changes.

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
- Keep the body short and concise (omit it entirely if not useful)")
   )
  "Alist of custom commit styles for gptel-magit. Each element is a cons cell
  where the CAR is the style name (string) and the CDR is the prompt string."
  :type '(repeat (cons (string :tag "Style Name") (string :tag "Prompt Text")))
  :group 'gptel-magit)

(defun gptel-magit-set-commit-style (style-name)
  "Set the `gptel-magit-commit-prompt` based on STYLE-NAME.
STYLE-NAME should be one of the names defined in
`gptel-magit-commit-styles-alist`.

Interactively, prompts the user to choose a style."
  (interactive
   (let ((available-styles (mapcar #'car gptel-magit-commit-styles-alist)))
     (list (completing-read "Choose commit style for gptel-magit: "
                            available-styles
                            nil t nil nil))))

  (let* ((selected-pair (assoc style-name gptel-magit-commit-styles-alist))
         (prompt-to-use (cdr selected-pair)))
    (if selected-pair
        (progn
          (setq gptel-magit-commit-prompt prompt-to-use)
          (message "gptel-magit commit style set to '%s'." style-name))
      (error "Invalid commit style name: %S. Not found in `gptel-magit-commit-styles-alist`." style-name))))

(defcustom gptel-magit-commit-prompt
  ;;changed to a 'cdr' with a 'assoc'
  (cdr (assoc "Conventional Commits" gptel-magit-commit-styles-alist))
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


(defun gptel-magit--format-commit-message (message)
  "Format commit message MESSAGE nicely."
  (with-temp-buffer
    (insert message)
    (text-mode)
    (setq fill-column git-commit-summary-max-length)
    (fill-region (point-min) (point-max))
    (buffer-string)))

(defun gptel-magit--request (&rest args)
  "Call `gptel-request` with ARGS.

Respects configured model/backend options."
  (declare (indent 1))
  (let* ((gptel-backend (or gptel-magit-backend gptel-backend))
         (gptel-model (or gptel-magit-model gptel-model)))
    (apply #'gptel-request args)))

(defun gptel-magit--generate (callback)
  "Generate a commit message for current magit repo.
Invokes CALLBACK with the generated message when done."
  (let ((diff (magit-git-output "diff" "--cached")))
    (gptel-magit--request diff
      :system gptel-magit-commit-prompt
      :context nil
      :callback (lambda (response _info)
                  (let ((msg (gptel-magit--format-commit-message response)))
                    (funcall callback msg))))))

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
    :callback (lambda (response _info)
                (gptel-magit--show-diff-explain response)))
  (message "magit-gptel: Explaining diff..."))

(defun gptel-magit-diff-explain ()
  "Ask for an explanation of diff at current section."
  (interactive)
  (when-let* ((section (magit-current-section))
              (start (oref section content))
              (end (oref section end))
              (content (buffer-substring start end)))
    (gptel-magit--do-diff-request content)))

;;;###autoload
(defun gptel-magit-install ()
  "Install gptel-magit functionality."
  (define-key git-commit-mode-map (kbd "M-g") 'gptel-magit-generate-message)
  (transient-append-suffix 'magit-commit #'magit-commit-create
    '("g" "Generate commit" gptel-magit-commit-generate))
  (transient-append-suffix 'magit-diff #'magit-stash-show
    '("x" "Explain" gptel-magit-diff-explain)))

(provide 'gptel-magit)
;;; gptel-magit.el ends here
