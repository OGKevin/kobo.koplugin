---
applyTo: "docs/**/*.md"
---

# Documentation review guidelines

This document tells you how to review Markdown documentation in this repository. Follow these steps
each time you review content so docs stay accurate, usable, and consistent.

## High-level audience guidance

- If a file lives under `docs/dev/` it is technical documentation. Assume the reader has general
  technical knowledge; focus on correctness and completeness.
- All other files under `docs/` are user-facing. Write these so someone with little or no technical
  background can understand them — think "explain like I'm five (ELI5)". Prefer short sentences,
  concrete examples, and step-by-step instructions.

## Before you start

- Confirm the file belongs under the right directory (`docs/dev/` vs `docs/`) based on its audience
  and adjust if necessary. If you move it, update any links that pointed to the old path.

## Review checklist

- Links
  - Verify all Markdown links that point to files in the repo actually resolve to existing files
    (relative paths and case-sensitive filenames).
  - Ensure external links point to the intended resource and are not stale (open them to confirm
    content, where practical).
  - If a link targets generated output (e.g. `book/`), prefer linking to the source under `docs/`
    instead.
- Cross-references
  - Make sure references to other docs (for example `docs/SUMMARY.md`, `README.md`, or other pages)
    are up to date.
  - If the doc introduces a new page, ensure `docs/SUMMARY.md` is updated to include it.
- Content quality
  - Clarity: Is the purpose of the document clear in the first paragraph?
  - Audience: Is the tone appropriate for the intended audience (ELI5 for users, direct/precise for
    devs)?
  - Accuracy: Verify technical steps, commands, filenames, and expected outputs.
  - Examples: Where helpful, include minimal, copy-paste-ready examples.
  - Brevity and structure: Use headings, short paragraphs, and bullet points to improve scanning.
- Style and formatting
  - Wrap prose at ~100 characters.
  - Use consistent heading structure and meaningful headings.
  - Use code formatting (backticks) for filenames, commands, and inline code.
  - Prefer active voice and imperative mood for procedural steps.
- Media and assets
  - Ensure images and other assets referenced by the doc exist at the specified paths.
  - Confirm alt text is present for accessibility.
- Spelling, grammar, and typos
  - Fix typos and grammatical errors. Prefer meaningful commit messages for edits.

## Reporting issues

- When uncertain about intended behavior or audience, ping the original author or the maintainers
  for clarification.
