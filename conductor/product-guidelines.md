# Product Guidelines: gptel-magit

## Design Language
`gptel-magit` should feel like a native extension of Magit. Its visual and functional elements should be indistinguishable from Magit's own UI, ensuring a seamless user experience.

### Tone and Voice
- **Technical/Professional:** Documentation and UI messages should be clear, informative, and authoritative. Avoid jargon unless necessary, and focus on providing actionable information to the user.
- **Native/Standard:** The project's brand identity is rooted in the stability and reliability of the Emacs and Magit ecosystems. It should feel like a well-integrated, "standard" tool rather than a flashy experiment.

## User Experience (UX) Principles
- **Magit-Native UI:** Adhere strictly to Magit's transient-based navigation and command structures. Users should feel at home immediately without needing to learn new UI paradigms.
- **Minimal Disruption:** The integration should be unobtrusive. LLM features should be easily accessible but should not interfere with standard Magit workflows for users who do not wish to use them.
- **Clear Status Feedback:** Provide clear feedback when an LLM request is in progress, ensuring the user is never left wondering about the package's state.

## Implementation Guidelines
- **Extensibility:** Design for future extensions (e.g., more prompts, different LLM backends).
- **Customizability:** Allow users to override defaults (prompts, models) through Emacs' customization system (`defcustom`).
- **Standard Formatting:** Ensure all generated commit messages and diff explanations follow standard Git and Markdown conventions.
