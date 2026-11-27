---
name: review-loop
description: Run an iterative code review with a fresh Claude Code, Codex or Antigravity CLI reviewer, implement agreed fixes, and re-review until consensus. Use when asked for another agent to review local changes and iterate on findings.
---

# Review loop

You are the author. Drive a separate fresh-context reviewer through headless CLI calls. The reviewer reports findings only; you adjudicate them, implement agreed fixes, and request re-review. Do not commit unless the user explicitly asks.

## Choose the reviewer

- Claude models (`opus`, `sonnet`, `haiku`, `fable`, or `claude-*`) use `claude`; GPT/Codex models use `codex`; Gemini models (`gemini-*`) use Antigravity's `agy`, whose effort is part of the model name (`agy models` lists them, such as `gemini-4-neon-high`).
- If no model is specified, use the latest Claude Opus model, unless you are a Claude model yourself in which case you should use the latest GPT Sol model.
- Set the reasoning/effort to medium, unless the user has explicitly asked otherwise.
- Pass the requested model directly. If the CLI rejects it, report that and ask the user to choose another rather than probing caches or making test calls.
- Run every turn from the same directory, append `< /dev/null`, and allow at least 10 minutes.
- Claude uses `--permission-mode auto` on every turn. Antigravity needs no permission flags to read files and run commands such as `git diff` (see [Antigravity](#antigravity) for what it can't do headless). Codex uses `--ask-for-approval on-request` on every turn, unless it is configured to bypass permissions (in which case you'll get an error like `error: the argument '--dangerously-bypass-approvals-and-sandbox' cannot be used with '--ask-for-approval <APPROVAL_POLICY>'`). Do not set tool allowlists or sandbox modes.

## Define the scope

Give the reviewer exact commands for the requested changes:

- **Branch:** compare `HEAD` with the appropriate remote default branch, e.g. `git diff origin/main...HEAD`. Fetch only when a current remote comparison is required and appropriate.
- **Working tree:** use `git diff`, `git diff --cached`, and `git status --short`, then inspect relevant untracked files.
- **Both:** provide both sets of commands.

Do not assume `origin/main`, a clean tree, or committed changes. For multiple repositories, run from a common parent and use absolute `git -C <repo>` commands; Codex refuses to run outside a git repository, so add `--skip-git-repo-check` to every `codex exec` and `codex exec resume` call there. Include relevant product context, companion repository paths or MCP sources, and contract owners.

A review is only valid if the reviewer was able to read all the context relevant to the change, including code outside the reviewed repository such as companion repositories, dependencies, MCP sources and contract owners. A reviewer that cannot reach that context will miss issues while still sounding confident, so treat a review done without it as no review at all.

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

Antigravity, with the prompt on stdin (better than `-p` for long prompts, and it fails at once when logged out, where `-p` waits a minute for a login code):

```bash
review_dir=$(mktemp -d "${TMPDIR:-/tmp}/review-loop.XXXXXX"); echo "$review_dir"
printf '%s' "<review prompt>" | agy --model <model> --output-format json \
  > <review-dir>/review-1.json
jq -r .conversation_id,.status <review-dir>/review-1.json; jq -r .response <review-dir>/review-1.json
```

Remember the `conversation_id`. A `status` other than `SUCCESS` is a failed turn; one transient failure ("empty conversation id") succeeded on retry.

Use this prompt, adapted to the task:

```text
You are the reviewer in an iterative review loop with another agent acting as the author. Review and report findings only; do not modify the implementation. The author will respond, implement agreed fixes, and ask you to re-review.

Product context: <purpose and constraints>.
External context: <companion repos, MCP sources, and contract owners>.
Review scope: <exact branch and/or working-tree commands>.

While reviewing, read all context relevant to the change, including external code (companion repositories, dependencies, MCP sources, contract owners) and anything else the change interacts with. If you cannot access any of it, for example because a tool call fails, is denied or is sandboxed, or a path, repository or MCP server is unavailable, do not continue the review and do not report findings based on partial context. Instead, list exactly what you could not access, the command or tool you tried, and the error, then end with STATUS: blocked.

Review for correctness, regressions, edge cases, maintainability, integration behavior, and missing verification. Verify external contracts at their authoritative source rather than trusting local types, tests, comments, or documentation alone. Do not run tests, linting or formatting for the sake of it: run targeted tests when useful to investigate an issue, but do not duplicate routine CI without a clear reason.

Number findings F1, F2, ... with severity, evidence, and a recommendation. Judge the author's later responses on their merits: concede when the author is right and hold firm when not.

End with exactly one line: STATUS: issues-remaining, STATUS: consensus, or STATUS: blocked
```

Do not seed the reviewer with your suspected findings or intended fixes.

## Iterate

After every reviewer turn, check its full output as well as its final message for failed, denied or sandboxed tool calls, and for unavailable repositories, paths or MCP servers. If the reviewer reports `STATUS: blocked`, or you see it could not read relevant context even though it did not say so, abort the loop immediately: do not adjudicate its findings, do not paste the missing context in yourself as a workaround, and do not continue with a degraded review. Report to the user what the reviewer could not access and the errors, so the underlying problem can be fixed before the review is re-run.

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

When needed, use `codex --ask-for-approval on-request exec resume ...`.

Antigravity:

```bash
printf '%s' "<author response>" | agy --conversation <conversation-id> --model <model> \
  --output-format json > <review-dir>/review-N.json
jq -r .response <review-dir>/review-N.json
``` Point the reviewer at the current diff; commits are not required.

## Finish

- Stop at `STATUS: consensus` when you also have no unresolved disagreement, and only if the reviewer had access to all relevant context in every round.
- Abort at `STATUS: blocked` or any other sign the reviewer could not read relevant context, as described above. Report the review as invalid, not as consensus or partial results.
- Stop after 5 rounds, or when one finding has stalled twice; report both positions and your recommendation without claiming consensus.
- Never claim consensus was reached if it was not, and never silently drop a finding you did not fix.
- Remove the temporary output directory.
- Report the reviewer/model, rounds, accepted fixes, rejected findings, and unresolved disagreements.

## Antigravity

What headless `agy` does on this machine, as of late 2026:

- `--mode auto` isn't available on this account, so it runs in the default mode, where nobody can answer a permission prompt. Reading files and most shell commands go ahead, but writing or editing a file is refused unless allowed. Some shell commands are refused too, without saying which, so when it's to change files also allow every command: `--settings '{"permissions":{"allow":["write_file(<abs dir>)","edit_file(<abs dir>)","command(*)"]}}'`. Name the directory without a glob: a rule with one, such as `<abs dir>/**`, makes every shell command fail with "sandbox configuration error: ... globs not supported", even `ls`. The directory rule covers files in its subdirectories. A rule for a path under `/tmp` didn't match, probably because `/tmp` is a link to `/private/tmp`.
- A refused command doesn't fail the turn: it can still report `status: SUCCESS`, with an empty `response` and `denied_actions` listing `{"action":"command"}`, sometimes after stalling for over an hour and using up the account's quota (an `Individual quota reached` error, resetting an hour or two later). After every turn, check `denied_actions` and `git status` as well as `status`, and tell it in the prompt to stop and name any command that's refused rather than trying others.
- A long conversation can grow past a million input tokens a turn. For later rounds of a long task, such as further batches of fixes, start a fresh conversation with a self-contained prompt rather than resuming.
- Deny rules don't stop its shell tool, and its terminal sandbox can't start the Nix zsh here, so commands it runs fall back to running unsandboxed without asking Allow rules don't confine it either: with the rules above, its file tool wrote outside the allowed directory without asking. Never rely on its settings to keep it read-only or inside a directory. To turn every tool off, run it in a directory with `.agents/hooks.json` containing a `PreToolUse` hook with matcher `*` whose command prints `{"decision":"deny","reason":"..."}`.
- It reads `~/.gemini/AGENTS.md` (these instructions) and the `AGENTS.md` in its working directory, and, inside a git repo, those up to the repo's root. A `.git` file containing `gitdir: /nonexistent` in its working directory stops that walk.
- Its web search returns `vertexaisearch.cloud.google.com` redirect links, so ask for the real destination URL when it cites sources.
- Never pass `--remote-agent`, which runs conversations in the cloud.

