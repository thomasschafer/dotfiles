# dotfiles

## macOS

```sh
git clone https://github.com/thomasschafer/dotfiles.git ~/Development/Personal/dotfiles
cd ~/Development/Personal/dotfiles
./setup.sh personal
```

Re-run `setup.sh` (or `dp`) to apply changes. Setup clones the repos it builds from source, such as Helix and herdr, but never pulls them afterwards; pull one yourself and re-run setup to rebuild it. Anything already running keeps the old build until restarted.

On hosts with `enableDependabotReview`, it also installs the weekly Dependabot review job and prompts you to log in to the Claude CLI and for its GitHub and Todoist tokens if they're missing. Create them first, as described in [dependabot-review/README.md](dependabot-review/README.md#setup), or skip the prompt and run `./dependabot-review/setup-secrets` later.

On hosts with `enableTodoistBackup`, it installs the Todoist backup job and prompts you to set up its Todoist credentials and deploy key if they're missing; see [todoist-backup/README.md](todoist-backup/README.md#setup).

On hosts with `enableHealthTracking` or `enableWorkshop`, it clones those repos (and, for Workshop, the advent-of-code repo it keeps solutions in) and runs them in the background, then prints the link to open each on your phone.

Setup ends by checking what it can't do for you: each background service is running, you're logged in to GitHub, Claude Code and Tailscale, and `workshop doctor` is happy (the Advent of Code cookie, packages and so on). Anything missing is listed with how to fix it, so on a new machine, run `dp` again until it's quiet.

### What setup can't check

- Restoring secrets from the password manager when prompted: the health-tracking backup key, and the Dependabot review and Todoist backup tokens.
- On your phone, opening each printed link, adding it to the home screen, and in Workshop, turning on notifications.

## Adding a host

Create `modules/hosts/<name>/default.nix`, setting every option declared in [modules/host-options.nix](modules/host-options.nix), then run `./setup.sh <name>`.
