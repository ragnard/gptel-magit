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
;; magit.  Currently, it adds functionality for generating commit
;; messages.

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'magit)
(require 'subr-x)

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

(defcustom gptel-magit-tag-prompt
  "You are an expert at writing annotated Git tag messages.
Your job is to write a clear, concise release summary for the changes between a previous tag and the new tag target.

Use the supplied commit list, diffstat, and diff to identify the notable changes. Prefer a short title followed by concise bullet points when useful.

Only return the tag message. Do not include any additional meta-commentary about the task. Do not include the raw diff output in the tag message."
  "The prompt to use for generating annotated tag messages.
The input contains the previous tag, the new tag target, commit
subjects, a diffstat, and the diff between those revisions."
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

(defvar-local gptel-magit--rationale-submit-function nil
  "Function called with rationale text from `gptel-magit-rationale-mode'.")

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

(defun gptel-magit--streaming-callback (callback &optional what transform)
  "Return a gptel streaming callback for CALLBACK.
Call CALLBACK once, after all streaming chunks arrive.  WHAT is
used in diagnostic messages.  TRANSFORM, when non-nil, is applied
to the completed response before CALLBACK is called."
  (let ((chunks nil)
        (what (or what "response")))
    (lambda (response info)
      (cond
       ((and (stringp response) (plist-get info :stream))
        (push response chunks))
       ((stringp response)
        (funcall callback (if transform (funcall transform response) response)))
       ((eq response t)
        (let ((text (apply #'concat (nreverse chunks))))
          (funcall callback (if transform (funcall transform text) text))))
       ((and (consp response) (eq (car response) 'reasoning))
        nil)
       ((plist-get info :error)
        (message "gptel-magit: Error generating %s: %s"
                 what
                 (or (plist-get (plist-get info :error) :message)
                     (plist-get info :error))))
       ((null response)
        (message "gptel-magit: Empty %s from LLM (%s)"
                 what (or (plist-get info :status) "unknown status")))))))

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
      :stream t
      :callback (gptel-magit--streaming-callback
                 callback "commit message" #'gptel-magit--format-commit-message))))

(defun gptel-magit--tag-message-buffer-p ()
  "Return non-nil if the current buffer edits a Git tag message."
  (and buffer-file-name
       (string= (file-name-nondirectory buffer-file-name) "TAG_EDITMSG")))

(defun gptel-magit--format-tag-message (message)
  "Format generated tag MESSAGE for insertion."
  (concat (string-trim-right message) "\n"))

(defun gptel-magit--insert-message-at-top (message)
  "Insert MESSAGE at the top of the current message buffer."
  (save-excursion
    (goto-char (point-min))
    (insert (string-trim-right message) "\n\n")))

(defun gptel-magit--read-previous-tag (target)
  "Read the previous tag to compare against TARGET."
  (magit-completing-read
   (format "Previous tag for %s" target)
   (magit-list-tags) nil t nil 'magit-revision-history
   (magit-get-current-tag target)))

(defun gptel-magit--read-tag-generation-args (&optional args)
  "Read arguments needed to create a generated annotated tag.
ARGS are the active `magit-tag' transient arguments."
  (let* ((args (or args (magit-tag-arguments)))
         (tag (magit-completing-read "Create tag" (magit-list-tags)))
         (target (magit-read-branch-or-commit "Place tag on"))
         (previous (gptel-magit--read-previous-tag target)))
    (list tag target previous args)))

(defun gptel-magit--tag-request-text (previous target tag rationale)
  "Build the tag-generation request for PREVIOUS..TARGET.
TAG is the tag being generated, or nil when generating inside an
existing tag message buffer.  Optional RATIONALE provides extra
user context."
  (let* ((range (format "%s..%s" previous target))
         (commits (magit-git-output "log" "--reverse" "--format=%h %s" range))
         (stat (magit-git-output "diff" "--stat" previous target))
         (diff (magit-git-output "diff" previous target)))
    (concat
     (and tag (format "New tag: %s\n" tag))
     (format "Previous tag: %s\nNew tag target: %s\nRange: %s\n\n"
             previous target range)
     (and (and rationale (not (string-empty-p rationale)))
          (format "Release rationale: %s\n\n" rationale))
     "Commits:\n" commits "\n\n"
     "Diffstat:\n" stat "\n\n"
     "Diff:\n" diff)))

(defun gptel-magit--generate-tag-message (previous target callback
                                                   &optional tag rationale)
  "Generate a tag message for PREVIOUS..TARGET.
Invoke CALLBACK with the generated message.  Optional TAG is the
new tag name, and optional RATIONALE gives user context."
  (gptel-magit--request
      (gptel-magit--tag-request-text previous target tag rationale)
    :system gptel-magit-tag-prompt
    :context nil
    :stream t
    :callback (gptel-magit--streaming-callback
               callback "tag message" #'gptel-magit--format-tag-message)))

(defun gptel-magit--tag-annotated-arg-p (arg)
  "Return non-nil if ARG requests an annotated tag."
  (and (stringp arg)
       (string-match-p "\\`--\\(annotate\\|sign\\|local-user\\)" arg)))

(defun gptel-magit--tag-create-with-message (tag target previous args
                                                 &optional rationale)
  "Create TAG at TARGET using a generated message since PREVIOUS.
ARGS are the active `magit-tag' transient arguments.  Optional
RATIONALE provides extra context for generation."
  (let ((args (copy-sequence args)))
    (unless (cl-some #'gptel-magit--tag-annotated-arg-p args)
      (cl-pushnew "--annotate" args :test #'equal))
    (cl-pushnew "--edit" args :test #'equal)
    (gptel-magit--generate-tag-message
     previous target
     (lambda (message)
       (magit-run-git-with-editor "tag" args (list "-m" message) tag target))
     tag rationale))
  (message "magit-gptel: Generating tag message..."))

(defun gptel-magit--generate-tag-message-in-buffer (&optional rationale)
  "Generate a tag message into the current tag edit buffer.
Optional RATIONALE provides extra context for generation.  The tag
target defaults to HEAD because Git does not expose the pending tag
object in TAG_EDITMSG."
  (let* ((buffer (current-buffer))
         (target "HEAD")
         (previous (gptel-magit--read-previous-tag target)))
    (gptel-magit--generate-tag-message
     previous target
     (lambda (message)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (gptel-magit--insert-message-at-top message))))
     nil rationale))
  (message "magit-gptel: Generating tag message..."))

(defun gptel-magit-tag-generate (&optional args)
  "Create an annotated tag with a generated tag message.
Uses ARGS from the `magit-tag' transient."
  (interactive (list (magit-tag-arguments)))
  (pcase-let ((`(,tag ,target ,previous ,args)
               (gptel-magit--read-tag-generation-args args)))
    (gptel-magit--tag-create-with-message tag target previous args)))

(defun gptel-magit-tag-generate-with-rationale (&optional args)
  "Create an annotated tag with a generated tag message and rationale.
Uses ARGS from the `magit-tag' transient."
  (interactive (list (magit-tag-arguments)))
  (pcase-let ((`(,tag ,target ,previous ,args)
               (gptel-magit--read-tag-generation-args args)))
    (gptel-magit--prompt-for-rationale
     (lambda (rationale)
       (gptel-magit--tag-create-with-message
        tag target previous args rationale)))))

(defun gptel-magit-generate-message ()
  "Generate a commit or tag message in a Git message buffer."
  (interactive)
  (cond
   ((gptel-magit--tag-message-buffer-p)
    (gptel-magit--generate-tag-message-in-buffer))
   ((magit-commit-message-buffer)
    (gptel-magit--generate (lambda (message)
                             (with-current-buffer (magit-commit-message-buffer)
                               (save-excursion
                                 (goto-char (point-min))
                                 (insert message)))))
    (message "magit-gptel: Generating commit message..."))
   (t
    (user-error "No commit or tag message in progress"))))

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
    :stream t
    :callback (gptel-magit--streaming-callback
               #'gptel-magit--show-diff-explain "diff explanation"))
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
  (setq-local gptel-magit--rationale-submit-function nil)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert ";;; WHY are you making these changes? (optional)\n")
    (insert ";;; Press C-c C-c to generate message, C-c C-k to cancel\n")
    (insert ";;; Leave empty to generate without rationale\n")
    (insert ";;; ────────────────────────────────────────────────────────\n")
    (add-text-properties (point-min) (point)
                         '(face font-lock-comment-face read-only t))
    (insert "\n")
    (goto-char (point-max))))

(defun gptel-magit--prompt-for-rationale (submit-function)
  "Prompt for rationale and call SUBMIT-FUNCTION with the result."
  (let ((buffer (get-buffer-create gptel-magit-rationale-buffer)))
    (with-current-buffer buffer
      (gptel-magit-rationale-mode)
      (gptel-magit--setup-rationale-buffer)
      (setq-local gptel-magit--rationale-submit-function submit-function))
    (pop-to-buffer buffer)))

(defun gptel-magit--submit-rationale ()
  "Submit the rationale buffer content and proceed with generation."
  (interactive)
  (let ((rationale (string-trim
                    (buffer-substring-no-properties
                     (save-excursion
                       (goto-char (point-min))
                       (while (and (not (eobp))
                                   (get-text-property (point) 'read-only))
                         (forward-char))
                       (point))
                     (point-max))))
        (submit-function gptel-magit--rationale-submit-function))
    (quit-window t)
    (if submit-function
        (funcall submit-function rationale)
      (gptel-magit--generate
       (lambda (message)
         (with-current-buffer gptel-magit--current-commit-buffer
           (save-excursion
             (goto-char (point-min))
             (insert message))))
       rationale)
      (message "magit-gptel: Generating commit message with rationale..."))))

(defun gptel-magit--cancel-rationale ()
  "Cancel rationale input and abort commit generation."
  (interactive)
  (quit-window t)
  (message "Commit generation canceled."))

(defun gptel-magit-generate-message-with-rationale ()
  "Generate a commit or tag message with rationale."
  (interactive)
  (cond
   ((gptel-magit--tag-message-buffer-p)
    (let ((buffer (current-buffer)))
      (gptel-magit--prompt-for-rationale
       (lambda (rationale)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (gptel-magit--generate-tag-message-in-buffer rationale)))))))
   ((magit-commit-message-buffer)
    (setq gptel-magit--current-commit-buffer (magit-commit-message-buffer))
    (let ((buffer (get-buffer-create gptel-magit-rationale-buffer)))
      (with-current-buffer buffer
        (gptel-magit-rationale-mode)
        (gptel-magit--setup-rationale-buffer))
      (pop-to-buffer buffer)))
   (t
    (user-error "No commit or tag message in progress"))))

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
  (transient-append-suffix 'magit-tag #'magit-tag-create
    '("g" "Generate tag" gptel-magit-tag-generate))
  (transient-append-suffix 'magit-tag #'gptel-magit-tag-generate
    '("R" "Generate with rationale" gptel-magit-tag-generate-with-rationale))
  (transient-append-suffix 'magit-diff #'magit-stash-show
    '("x" "Explain" gptel-magit-diff-explain)))

(provide 'gptel-magit)
;;; gptel-magit.el ends here
