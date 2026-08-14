---
name: review-loop
description: Run an iterative code review with a fresh Claude Code or Codex CLI reviewer, implement agreed fixes, and re-review until consensus. Use when asked for another agent to review local changes and iterate on findings.
---

# Review loop

You are the author. Drive a separate fresh-context reviewer through headless CLI calls. The reviewer reports findings only; you adjudicate them, implement agreed fixes, and request re-review. Do not commit unless the user explicitly asks.

## Choose the reviewer

- Claude models (`opus`, `sonnet`, `haiku`, `fable`, or `claude-*`) use `claude`; GPT/Codex models use `codex`.
- If no model is specified, use the latest Claude Opus model, unless you are a Claude model yourself in which case you should use GPT-5.6-Sol.
- Pass the requested model directly. If the CLI rejects it, report that and ask the user to choose another rather than probing caches or making test calls.
- Run every turn from the same directory, append `< /dev/null`, and allow at least 10 minutes.
- Claude uses `--permission-mode auto` on every turn. Codex uses `--ask-for-approval on-request` on every turn, unless it is configured to bypass permissions (in which case you'll get an error like `error: the argument '--dangerously-bypass-approvals-and-sandbox' cannot be used with '--ask-for-approval <APPROVAL_POLICY>'`). Do not set tool allowlists or sandbox modes.

## Define the scope

Give the reviewer exact commands for the requested changes:

- **Branch:** compare `HEAD` with the appropriate remote default branch, e.g. `git diff origin/main...HEAD`. Fetch only when a current remote comparison is required and appropriate.
- **Working tree:** use `git diff`, `git diff --cached`, and `git status --short`, then inspect relevant untracked files.
- **Both:** provide both sets of commands.

Do not assume `origin/main`, a clean tree, or committed changes. For multiple repositories, run from a common parent and use absolute `git -C <repo>` commands. Include relevant product context, companion repository paths or MCP sources, and contract owners.

## Start the reviewer

For Codex, first create and remember a unique output directory:

```bash
review_dir=$(mktemp -d "${TMPDIR:-/tmp}/review-loop.XXXXXX"); echo "$review_dir"
```

Claude:

```bash
session_id=$(uuidgen); echo "$session_id"
claude -p "<review prompt>" --model <model> --session-id "$session_id" \
  --permission-mode auto < /dev/null
```

Codex:

```bash
codex exec -m <model> -o <review-dir>/review-1.txt "<review prompt>" \
  < /dev/null > <review-dir>/review-1-full.txt 2>&1
cat <review-dir>/review-1-full.txt; cat <review-dir>/review-1.txt
```

When Codex is not already in yolo mode, start with `codex --ask-for-approval on-request exec ...`. Extract and remember the `session id:` from the full output.

Use this prompt, adapted to the task:

```text
You are the reviewer in an iterative review loop with another agent acting as the author. Review and report findings only; do not modify the implementation. The author will respond, implement agreed fixes, and ask you to re-review.

Product context: <purpose and constraints>.
External context: <companion repos, MCP sources, and contract owners>.
Review scope: <exact branch and/or working-tree commands>.

Review for correctness, regressions, edge cases, maintainability, integration behavior, and missing verification. Verify external contracts at their authoritative source rather than trusting local types, tests, comments, or documentation alone. Do not run tests, linting or formatting for the sake of it: run targeted tests when useful to investigate an issue, but do not duplicate routine CI without a clear reason.

Number findings F1, F2, ... with severity, evidence, and a recommendation. Judge the author's later responses on their merits: concede when the author is right and hold firm when not.

End with exactly one line: STATUS: issues-remaining or STATUS: consensus
```

Do not seed the reviewer with your suspected findings or intended fixes.

## Iterate

For each finding, decide whether you agree, implement agreed fixes in the working tree, and reply by finding number. Include what changed or why you disagree, then ask the reviewer to re-run the exact current review commands.

Claude:

```bash
claude -p --resume <session-id> --permission-mode auto \
  "<author response>" < /dev/null
```

Codex:

```bash
codex exec resume <session-id> -m <model> \
  -o <review-dir>/review-N.txt "<author response>" < /dev/null \
  > <review-dir>/review-N-full.txt 2>&1
cat <review-dir>/review-N.txt
```

When needed, use `codex --ask-for-approval on-request exec resume ...`. Point the reviewer at the current diff; commits are not required.

## Finish

- Stop at `STATUS: consensus` when you also have no unresolved disagreement.
- Stop after 5 rounds, or when one finding has stalled twice; report both positions and your recommendation without claiming consensus.
- Never claim consensus was reached if it was not, and never silently drop a finding you did not fix.
- Remove the temporary output directory.
- Report the reviewer/model, rounds, accepted fixes, rejected findings, and unresolved disagreements.
