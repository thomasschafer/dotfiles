# todoist-backup

Backs up my whole Todoist account every four hours into a private git repo, as a safety net against agents (or anything else) deleting tasks. I'm not on Todoist Pro, so this is the only backup.

It is strictly read-only against Todoist. It authenticates with its own OAuth app limited to the `data:read` scope, and every request goes through one function (`send` in `todoist_backup/api.py`) that refuses anything but reads before making a connection. There's no code path that writes to Todoist: restoring is done by hand, guided by a restore plan.

## What it stores

The data lives in `~/.local/share/todoist-backup`, a clone of the private repo `thomasschafer/todoist-backup`. That's outside `~/Development`, where agents usually work, and outside the folders macOS privacy settings block for background jobs.

- `sync/`: everything a full sync returns (projects, sections, tasks, labels, filters, comments, reminders, collaborators, settings and so on), one file per resource type. Fields that change on every sync, like sync tokens and karma stats, are left out so commits only happen when something changed.
- `archived/`: archived projects, with their sections, tasks and comments, which a sync doesn't return.
- `completed/`: completed tasks by completion month. The first run fetches the full history; later runs fetch the last two weeks and merge, so completed tasks stay in the backup even if they're deleted later.

Files are pretty-printed with sorted keys and sorted by id, so `git log -p` shows what changed. Attachments are recorded (name, type, URL) but the files themselves aren't downloaded.

## Every run

1. Fetches everything and writes the snapshot.
2. Re-reads the written files and checks they parse and match what was fetched. If not, nothing is committed.
3. Fetches the live data again and compares ids per resource type. If they differ, probably because of edits during the run, it retries once, then alerts.
4. Compares active tasks and projects with the previous snapshot. If more than 20, or more than 10%, disappeared (at least 3, not counting completed or archived ones), it still commits but raises an alert that stays on screen.
5. Commits if anything changed and pushes to GitHub.

Offline runs exit quietly. Alerts other than deletions repeat at most once a day.

## Protecting the backup

The job pushes with a deploy key (`~/.ssh/todoist-backup_ed25519`) that only works for the data repo, using pinned GitHub host keys and none of your other git or SSH config. It never force-pushes. Before pushing, it checks that GitHub's history and the local clone's history are consistent. If either was rewritten, or GitHub's branch was deleted, it alerts and stops pushing (or restores the branch), so destroying the backup means destroying both copies before the next run. If the local clone goes missing, it's re-cloned from GitHub.

Claude Code is denied access to the data repo and deploy key (`claude/settings-overrides.json`). That only stops accidents: anything running as your user can read them, and your `gh` login can push to the repo. GitHub branch protection would stop force-pushes, but needs a paid plan for private repos. A dedicated GitHub machine account owning the repo would stop the `gh` login reaching it.

Secrets: the OAuth credentials are stored as one Keychain item, `todoist-backup`, and never printed, logged or written to disk. Before each commit the job refuses to proceed if a credential or private key appears in the data. The dotfiles have gitleaks as a pre-commit hook and TruffleHog in CI.

## Setup

Enabling `enableTodoistBackup` for a host and running `./setup.sh <host>` (or `dp`) installs the `todoist-backup` command and the launchd agent, then warns about anything missing. On a new machine you need to do two things by hand.

### Credentials

1. Open the [App Management Console](https://app.todoist.com/app/settings/integrations/app-management) and create an app (any name, e.g. "todoist-backup"). Set its OAuth redirect URL to `http://localhost:8723/callback`.
2. Run `todoist-backup setup-token`. It asks for the client ID and secret (the secret prompt is hidden), opens Todoist so you can approve read-only access, and stores the credentials in the Keychain. It refuses to store a token with any scope beyond `data:read`.

Run it again whenever the job alerts that you need to re-authorise. Todoist's tokens last an hour and the job refreshes them itself. Refresh tokens change on every refresh, so if a refresh is ever lost (for example the Mac crashed mid-refresh) you'll need to authorise again.

### Deploy key

```sh
ssh-keygen -t ed25519 -N '' -C "todoist-backup@$(scutil --get LocalHostName)" -f ~/.ssh/todoist-backup_ed25519
gh repo deploy-key add ~/.ssh/todoist-backup_ed25519.pub -R thomasschafer/todoist-backup --allow-write --title "todoist-backup ($(scutil --get LocalHostName))"
```

The first run clones the data repo into `~/.local/share/todoist-backup`.

## Running by hand

```sh
todoist-backup run --verbose   # back up now
todoist-backup status          # is it healthy?
todoist-backup restore-plan    # compare the latest snapshot with your account
```

## Checking it's healthy

`todoist-backup status` shows the last successful run, the last attempt and its result, whether the launchd agent is loaded, whether credentials are present, the latest commit and the stored counts. It ends with `Healthy: yes` (and exit code 0) only if a backup succeeded in the last 24 hours. Logs are in `~/.local/state/todoist-backup/todoist-backup.log` (rotated at 1 MB, 5 kept); `launchd.log` next to it only catches crashes before logging starts.

You'll also get a notification if a run fails, verification fails, deletions are detected, the backup history looks tampered with, credentials need re-authorising, or there's been no successful backup for 24 hours.

## Restoring

`todoist-backup restore-plan` compares a snapshot with the live account, read-only, and prints what's missing or changed. It defaults to the latest snapshot; after a deletion alert, use the one before it:

```sh
todoist-backup restore-plan --ref HEAD~1             # the snapshot before the latest
todoist-backup restore-plan --before 2026-10-01      # the latest snapshot before a date
todoist-backup restore-plan --ref HEAD~1 --json      # full objects, for scripting a restore
```

Find a snapshot with `git -C ~/.local/share/todoist-backup log --oneline`; commits where deletions were detected start with `DELETIONS DETECTED`.

Reading the plan:

- Summary: per resource type, how many are missing, changed and new.
- "Missing tasks, deleted or otherwise gone": the ones to recreate, grouped by project, section and parent, with their description, due date (including whether it recurs), deadline, priority and labels.
- "Missing because completed since the snapshot": usually nothing to do. They're in `completed/` and in Todoist's completed view.
- "Missing projects/sections/labels/...": recreate these before the tasks inside them.
- "Changed": each field that differs, as snapshot value → live value. Ordering fields are ignored.
- "New since the snapshot": things created afterwards; nothing to restore.

Recreating deleted items gives them new ids, so a later restore plan still lists the originals as missing. Comments and completion history can't be recreated as they were; their full text is in the snapshot files.

## Development

```sh
uv run --with pytest pytest tests   # run from this directory
ruff check . && ruff format --check .
```

The tests mock the Todoist API and use a local bare repo as the remote. `tests/test_read_only.py` checks that every write-shaped request is refused before reaching the network, and that nothing outside `api.py` can make network calls.
