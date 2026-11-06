---
name: explain-diff
description: Explain a code change so a human can follow it, with the background and before/after diagrams first, then the key hunks of the diff annotated with what changed and why. Use when asked to explain, annotate or walk through a diff, branch, commit or pull request, or when someone says they're struggling to understand a change.
---

# Explain a diff

The reader can see the diff but can't follow it. Usually what's missing is the picture the change sits in: which systems or concepts are involved, how things flowed before, and how they flow now. Give them that first, then walk through the parts of the diff that matter, saying what each one changes and why.

This is an explanation, not a review. Don't hunt for bugs or suggest changes, but if you notice something wrong or surprising while explaining, say so plainly at the end.

If the reader names a particular part of the change, explain that in depth and cover the rest only as far as it's needed to follow it.

## Gather context

Always read the actual diff, even if you think you know what's in it. For a branch, compare with the merge base of the default branch, e.g. `git diff origin/main...HEAD`; for a working tree, `git diff` and `git diff --cached`; for a pull request, read it through whatever tool the environment provides. Don't assume the default branch's name or that the tree is clean.

If this session made the change, you already have most of the context, so you don't have to re-derive the why (although do pull in whatever additional context you need to help with the explanation or to clarify anything). Explain what the diff contains, not what you intended: edits get reverted and reworked along the way. Where alternatives were tried or rejected during the session, mention them if they explain why the final version looks the way it does. And don't skip background because the code feels familiar to you; the reader is asking because it isn't familiar to them.

In a fresh session:

- **Read the code around the change, not just the hunks.** Open the changed files and anything they call or are called by that the explanation depends on.
- **Find the why.** Read the commit messages, the pull request description and its discussion, and any linked issue. Where the reason isn't written down, say what the code implies and mark it as your reading.

Either way, check library behaviour you're about to describe against the source or documentation of the version in use, rather than from memory. An explanation that's confidently wrong is worse than none.

## Structure

1. **Background.** What the reader needs before the diff makes sense: the concepts, systems or library APIs the change hinges on, how things worked before and how they work after, and briefly why it changed. Use small diagrams where there's a flow, structure or sequence to show. Stay at the level of the design.
2. **Annotated diff.** The hunks that carry the change, most important first, each followed by a short note on what changed and why. Summarise mechanical changes in a line rather than showing them. Say whether a change preserves behaviour or alters it, and call out anything easy to misread, such as an order dependency or something deliberately left alone.
3. **Wrap-up.** A short paragraph on the rest: what the tests pin down, other files, and anything that looks wrong or worth a second look.

Write for someone who knows the language but not this codebase or the libraries involved, and scale the length with the change: a ten-line fix needs a few sentences of background and a hunk or two.

## Keep it digestible

For a large change, don't try to cover everything at once. Give the background and the few hunks that matter most, then offer to go deeper on the rest or on any part the reader picks.

Reply inline by default. If the reader asks for the full walkthrough of a large change, write it to a markdown file outside the repository (or somewhere already ignored, such as `$TMPDIR`), give them the path and a short summary inline, and don't commit it.
