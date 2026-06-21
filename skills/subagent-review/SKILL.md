---
name: subagent-review
description: Run and adjudicate an independent fresh-context subagent review of local work. Use when the user asks for a subagent review of changes.
---

# Subagent review

Use this workflow when the user asks for a review from a subagent.

## Prepare context

- Identify the user-visible goal.
- Share the task and important constraints with the subagent.
- Ask for a thorough, critical, PR-style review.
- Do not leak expected findings, suspected bugs, or intended fixes unless the subagent needs that information to review correctly.
- Tell the subagent not to modify files unless the user explicitly asked the subagent to make changes.

## Ask the subagent

Use a prompt shaped like this, adapted to the task:

```text
You are reviewing changes in <repo>. Please do a thorough, critical PR-style review.

Context: <short task summary and important constraints>.

Inspect changed files <give more context here e.g. relative to main via `git diff main...HEAD`>. Focus on correctness, regressions, maintainability, integration behavior, and missing verification. Do not modify files.

Return actionable findings only. For each finding include the exact file and line, a short snippet, severity, what is wrong, and the suggested fix. If there are no actionable findings, say so and mention residual risks or checks you could not run.
```

## Review the response

- Verify each finding against the local files before presenting it to the user.
- Check whether the finding still applies if the subagent reviewed stale context. If anything has changed, then ask the subagent to re-review.
- Decide whether you agree with each finding before proposing a fix.

## Report to the user

For each subagent finding, report:

- Exact location with file and line.
- Short snippet.
- Finding and severity.
- Whether you agree.
- Proposed fix if you agree, or why you disagree.

After findings, include any open questions or residual test gaps. If there are no findings, say that directly.
