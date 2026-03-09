# Initial Concept
Uses the gptel library to extend magit with LLM-powered functionality for generating commit messages and explaining diffs.

# Product Guide: gptel-magit

## Initial Concept
Uses the gptel library to extend magit with LLM-powered functionality for generating commit messages and explaining diffs.

## Product Vision
`gptel-magit` aims to be the standard way for Magit users to leverage Large Language Models directly within their Git workflow. By integrating seamlessly with existing Magit transients and buffers, it provides a powerful yet unobtrusive experience for developers who want to write better commits and understand their changes more deeply.

## Target Audience
- **Magit Users:** Existing Magit aficionados who want to boost their productivity with LLM-assisted workflows.
- **LLM Enthusiasts:** Developers who already use `gptel` and want to extend its capabilities to their Git operations.

## Key Goals
1. **LLM-Powered Commits:** Automate the tedious process of drafting high-quality, descriptive commit messages.
2. **Seamless Integration:** Provide a native Magit-like experience using transients and existing keymaps.
3. **Enhanced Understanding:** Help developers quickly grasp the essence of complex diffs through AI-generated summaries.

## Core Features
- **Commit Message Generation:** Generate a commit message based on staged changes directly from the Magit commit buffer or transient.
- **Diff Explanation:** Provide a concise Markdown summary of any diff section (hunk or file) within Magit.
- **Commit Style Support:** Support for different commit message styles, including standard Git and Conventional Commits.

## Future Roadmap
- **Log Summaries:** Summarize changes across multiple commits in a `magit-log` buffer.
- **Prompt Customization:** Allow users to define and select custom prompts for different Git tasks.
- **PR Automation:** Assist in drafting Pull Request descriptions and identifying potential review points.
