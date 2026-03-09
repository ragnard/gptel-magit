# Technology Stack: gptel-magit

## Core Language
- **Emacs Lisp (elisp):** The core language for extending the GNU Emacs text editor.

## Key Dependencies
- **Magit (4.0+):** A powerful and feature-rich Git interface for Emacs.
- **gptel (0.9.8+):** A general-purpose LLM client for Emacs, supporting multiple backends (OpenAI, Anthropic, Google, Ollama, etc.).

## Runtime Environment
- **Emacs (28.1+):** The primary runtime environment for the package.

## Tooling and Testing
- **Ert:** Emacs' built-in regression testing framework (standard for elisp projects).
- **Buttercup:** (Optional) Behavioral testing framework for Emacs Lisp.
- **package-lint:** A tool for linting Emacs Lisp packages to ensure they follow MELPA conventions.
