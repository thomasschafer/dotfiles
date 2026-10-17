# dependabot-review

A weekly job that reviews open Dependabot PRs on my personal repos with headless Claude Code, merges the safe ones, fixes easy breakages, splits mixed groups and flags everything else to Todoist.

In scope: repos owned by my account, not forks, not archived, with a `.github/dependabot.yml`. This is re-checked on every run.

## Layout

- `cleanup-archived`: one-off Phase 0 clean-up of Dependabot PRs on archived repos.
- `config-prs`: Phase 1, opens a PR per repo aligning its Dependabot config with `templates/`.
- `run`: scheduler entry point with the run guard, staleness alert and logging.
- `review-all`: reviews every open Dependabot PR, one at a time.
- `review-pr`: reviews one PR and carries out the outcome.
- `prompts/`, `verdict-schema.json`: what Claude is asked and must return.
- `config.sh`: dry-run flag, model, caps, cooldown and Todoist IDs.
- `nix/home.nix`: tools, plus the hourly launchd agent or systemd timer.

## Setup

`./setup.sh personal` or `dp` installs the tools and the hourly trigger, then runs `setup-secrets`. That script prompts for any token not yet in the keychain; run it again any time to add one you skipped. Create the tokens first:

- GitHub: a fine-grained token. Set the resource owner to your account and give it access to all repos, with these permissions:
  - Contents, Pull requests: read and write
  - Checks, Actions, Commit statuses: read

  Don't grant Administration or Workflows.
- Todoist: your API token, from Settings, Integrations, Developer.

They're stored as `dependabot-review-github` and `dependabot-review-todoist`, in the keychain on macOS or `secret-tool` on Linux.

The `claude` CLI must be installed and logged in at `~/.local/bin/claude`.

## How it runs

The trigger fires hourly, at login and after waking. `run` exits straight away unless no run has succeeded since the most recent Friday 20:00 local time, GitHub is reachable and no other run holds the lock. If the last success is more than 10 days old, it creates a Todoist task.

For each PR, `review-pr` checks out the head commit and runs `claude -p` with a pinned model, turn and spend caps, and an allowlist of tools. Claude gets no GitHub or Todoist token and no MCP servers. Builds and tests run through a wrapper that starts a container in a dedicated colima VM. Only `~/.local/state/dependabot-review/work` is mounted into that VM, so containers can't see your home directory, keychain or SSH keys.

Claude returns a verdict: merge, fix, split or flag. `review-pr` then checks it against fixed rules before acting:

- It only merges when every required check passes on the exact reviewed commit. Repos without required checks are never merged.
- Fixes may not touch manifests, lockfiles or `.github`, delete files, add ignore or allow annotations, or remove test assertions. They can also cover CI breakages unrelated to the update, such as a new toolchain lint, with one commit per cause.
- Splits may only change manifests and lockfiles that the original PR changed.

A revision that has already been reviewed is skipped, using a hidden marker in the PR comment. Todoist tasks are deduplicated by PR URL.

State, logs (kept for 28 days) and checkouts live in `~/.local/state/dependabot-review/`.

## Running by hand

```sh
./review-pr --preview owner/repo 123  # review one PR; print actions instead of taking them
./run --force                         # full run now, ignoring the weekly guard
```

`review-pr` without `--preview` and `run` need the tokens from setup. `run` reads them itself. For `review-pr`, export `GH_TOKEN` and `TODOIST_TOKEN` first.

`cleanup-archived` and `config-prs` use your normal `gh` login, since they need admin rights or the `workflow` scope. `config-prs --dry-run` prints the diffs without opening PRs.

## Dry run

`DRY_RUN=true` in `config.sh` makes the job comment its verdict, label flagged PRs and create Todoist tasks, but never merge, push or open PRs. Set it to `false` and rebuild to go live, since the job runs from the Nix store copy.
