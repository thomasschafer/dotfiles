---
name: review-loop
description: Iterative code review loop with a fresh reviewer agent (Claude Code or Codex CLI, any model, e.g. "review-loop with fable 5" or "with gpt 5.6 sol") driven headlessly. Use when asked to get changes reviewed by another agent and go back and forth to consensus, implementing agreed fixes between rounds.
---

# Review loop

You are the author. A separate, fresh-context agent is the reviewer, driven entirely through headless CLI invocations. You request a review, respond to findings, implement agreed changes, commit, and ask for re-review until you both reach consensus or hit the round cap.

The reviewer can be either Claude Code (`claude`) or Codex (`codex`), regardless of which tool you are. Pick based on what the user asked for.

## Choosing the reviewer CLI and model

Map the user's requested model to a CLI:

- Claude models (fable, opus, sonnet, haiku, or anything starting `claude-`) run via the `claude` CLI. Aliases `fable`, `opus`, `sonnet`, `haiku` work, as do full IDs like `claude-fable-5`. Normalize e.g. "claude fable 5" to `claude-fable-5` or just `fable`.
- GPT/Codex models run via the `codex` CLI. Normalize e.g. "gpt 5.6 sol" to the slug `gpt-5.6-sol`.
- If no model is specified, default to the latest Claude Opus model.

To discover available models:

- Codex: `jq -r '.models[].slug' ~/.codex/models_cache.json` lists current slugs with `.display_name` and `.description` alongside. If that file does not exist, the default model is the `model` key in `~/.codex/config.toml` — if the requested model matches that default, just use it (it is verifiably valid); otherwise run `/model` in the interactive `codex` TUI once to populate the cache.
- Claude Code: there is no CLI listing; the aliases above are stable, and the authoritative picker is `/model` in the interactive TUI. The default is the `model` key in `~/.claude/settings.json`. An invalid `--model` fails with a clear API error, so verifying a guess costs one cheap call: `claude -p "say OK" --model <candidate> < /dev/null`.

If the requested model matches neither CLI's known names, verify it as above rather than guessing; if it is not available, tell the user and list what is.

## Mechanics that must not be violated

Both CLIs:

- Run every invocation from the same directory each turn — the repo root for a single-repo review. Claude session resume fails outright from any other directory ("No conversation found"); Codex resumes but re-roots the reviewer's workdir at your current directory, so stay consistent.
- Diff against `origin/main` (or whatever the default branch is) after a fetch (`git fetch origin`, then `git diff origin/main...HEAD`), not a bare `main...HEAD`: a stale local `main` gives the wrong merge-base.
- Multi-repo changes (or out-of-tree docs): run the reviewer from a common parent directory and hand it absolute per-repo commands, e.g. `git -C /abs/path/<repo> diff origin/main...HEAD`. Codex re-roots to your cwd, so absolute paths are the robust choice. Share files outside any repo (e.g. a runbook) by copying them into the reviewer's readable tree (clean up afterward) or inlining them in the prompt.
- Append `< /dev/null` to every invocation, or both CLIs wait on piped stdin (claude stalls 3 seconds with a warning; codex reads stdin as extra prompt input).
- Use a generous timeout: review turns routinely take 3-5 minutes on a real diff. If your shell tool has a default timeout under 10 minutes, raise it for these calls.

Claude reviewer:

- Generate the session ID yourself with `uuidgen` and pass `--session-id` on the first call; plain text output needs no parsing on any turn.
- Pass `--model` only on the first call: the session keeps its model across resumes, and passing it again would override mid-conversation.
- If the machine is not set to auto permission mode, add `--allowedTools "Read,Grep,Glob,Bash(git diff*),Bash(git log*),Bash(git show*)"` to every invocation (flags do not persist across resumes). If the review looks like it never inspected the code, suspect denied permissions.
- For metadata (cost, errors), re-run with `--output-format json`: review text in `.result`, failures in `.is_error` and `.permission_denials`.

Codex reviewer:

- You cannot preset the session ID. Capture merged output to a file and extract the `session id:` line from the startup banner; the clean final message goes to a separate file via `-o`.
- Pass `-m <model>` on every turn including resumes: unlike claude, a resumed codex session reverts to the config default model if `-m` is omitted.
- `-s read-only` sandboxes the reviewer so it cannot modify files (also the `codex exec` default, but pass it explicitly on the first `codex exec`). Note: some codex builds' `exec resume` subcommand rejects `-s` (`error: unexpected argument '-s' found`) — a resumed session inherits the original sandbox, so omit `-s` on resume turns (keep `-m` and `-o`).
- `codex review --base <branch>` is a purpose-built one-shot alternative for the first review, but use `codex exec` for the loop so every turn works the same way.

## Round 1: request the review

Claude reviewer:

```bash
cd <repo-root>
session_id=$(uuidgen)
echo "$session_id"   # keep this; every later turn needs it

claude -p "<review prompt, see template>" \
  --model claude-fable-5 \
  --session-id "$session_id" < /dev/null
```

Codex reviewer:

```bash
cd <repo-root>
codex exec -m gpt-5.6-sol -s read-only \
  -o /tmp/review-1.txt "<review prompt, see template>" \
  < /dev/null > /tmp/review-1-full.txt 2>&1
session_id=$(sed -n 's/^session id: //p' /tmp/review-1-full.txt | head -1)
echo "$session_id"   # keep this; every later turn needs it
cat /tmp/review-1.txt
```

Review prompt template, adapted to the task:

```text
You are the code reviewer in an iterative review loop with another AI agent (the author). The author will respond to your findings, push back where it disagrees, make changes, and ask you to re-review.

Product context: <what the project is, what this change is for, constraints that matter>.

Review the changes: <exact command, e.g. git diff origin/main...HEAD>. Read surrounding code as needed for full context. Review in depth: correctness, regressions, edge cases, maintainability, integration behavior, missing verification.

Ground rules:
- Do not modify any files; only the author makes changes.
- Number findings (F1, F2, ...) with severity so we can reference them across turns.
- When the author responds, judge each point on its merits: concede when the author is right, hold firm when not.
- End every reply with exactly one line, either 'STATUS: issues-remaining' or 'STATUS: consensus'.
```

Do not leak your own suspicions or intended fixes into the prompt; the review should be independent.

## Rounds 2+: respond, implement, re-review

For each reviewer finding, decide on the merits whether you agree. Then in one turn: implement the fixes you agree with, commit them, and reply referencing findings by number.

Claude reviewer:

```bash
claude -p --resume "$session_id" "<author response, see template>" < /dev/null
```

Codex reviewer:

```bash
codex exec resume "$session_id" -m gpt-5.6-sol \
  -o /tmp/review-N.txt "<author response, see template>" \
  < /dev/null > /tmp/review-N-full.txt 2>&1   # no -s on resume; see Codex mechanics note
cat /tmp/review-N.txt
```

Author response template:

```text
Author here. Responses:
- F1: Agreed, fixed - <what you did>. See: git diff <prev>..HEAD
- F2: Pushing back - <your reasoning>.
Please re-review the fresh commits and respond to the pushback. Remember the STATUS line.
```

Point the reviewer at the fresh commits specifically (for example `git diff HEAD~2..HEAD`), not the whole branch again.

## Termination

- Stop when the reviewer emits `STATUS: consensus` and you have no open disagreements of your own.
- Cap the loop at 5 rounds. If you are still disagreeing, or the same finding has gone back and forth twice without movement, stop and escalate to the human: summarize each unresolved finding, both positions, and your recommendation. Defer these escalations to the end; first land everything you did agree on.
- Never claim consensus was reached if it was not, and never silently drop a finding you did not fix.

## Reporting back

When the loop ends, report to the human: which reviewer and model were used, rounds taken, findings raised, what was implemented (with commits), what was rejected and why the reviewer conceded, and any escalated disagreements.
