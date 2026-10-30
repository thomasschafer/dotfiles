# dotfiles

## macOS

```sh
git clone https://github.com/thomasschafer/dotfiles.git ~/Development/Personal/dotfiles
cd ~/Development/Personal/dotfiles
./setup.sh personal
```

Re-run `setup.sh` (or `dp`) to apply changes. Setup clones the repos it builds from source, such as Helix, herdr and the Herdr app (with herdr-core), and the Helix plugins it loads from their checkouts. Each run then fast-forwards them to their upstream and rebuilds any that changed. It only pulls a checkout that's on its tracked branch with no uncommitted changes or unpushed commits, and lists any it skipped, with why, at the end; `dp --no-pull` skips pulling altogether. Anything already running keeps the old build until restarted.

On hosts with `enableDependabotReview`, it also installs the weekly Dependabot review job and prompts you to log in to the Claude CLI and for its GitHub and Todoist tokens if they're missing. Create them first, as described in [dependabot-review/README.md](dependabot-review/README.md#setup), or skip the prompt and run `./dependabot-review/setup-secrets` later.

On hosts with `enableTodoistBackup`, it installs the Todoist backup job and prompts you to set up its Todoist credentials and deploy key if they're missing; see [todoist-backup/README.md](todoist-backup/README.md#setup).

On hosts with `enableAlmanac`, `enableHealthTracking` or `enableWorkshop`, it clones those repos (and, for Workshop, the advent-of-code repo it keeps solutions in), runs them in the background and serves each to your other devices with Tailscale Serve, on its own HTTPS port of the Mac's tailnet address (see [modules/tailscale-serve.nix](modules/tailscale-serve.nix)). It then prints the link to open each on your phone. Ports served by hand are left alone, as long as no app uses them.

On hosts with `enableOvis`, it installs [Ovis](https://github.com/devswha/ovis) as a herdr plugin, to use herdr's agents and terminals from your phone, and serves it the same way. It's pinned to a release in [modules/ovis.nix](modules/ovis.nix), which says how to update it; don't use Update in the app. On your phone, add its link to the home screen, then turn on alerts from the ⋯ menu.

[Rex](https://www.superlogical.com/rex/) works alongside herdr, from the same Helix, lazygit and yazi setup. Install the beta app by hand, then re-run setup to link its config ([rex/init.lua](rex/init.lua)) and set up its skill for Claude Code, Codex and OpenCode. In the app, open the command palette and run Import Theme File with `/Applications/Ghostty.app/Contents/Resources/ghostty/themes/Catppuccin Macchiato`, and in its settings, make Option act as Alt and turn on Remote Control, which kiosk needs to switch sessions.

Setup ends by checking what it can't do for you: each background service is running and served over Tailscale, you're logged in to GitHub, Claude Code and Tailscale, and `workshop doctor` is happy (the Advent of Code cookie, packages and so on). Anything missing is listed with how to fix it, so on a new machine, run `dp` again until it's quiet.

### What setup can't check

- Restoring secrets from the password manager when prompted: the health-tracking backup key, and the Dependabot review and Todoist backup tokens.
- On your phone, opening each printed link, adding it to the home screen, and in Workshop, turning on notifications.

### Secrets

Secrets live in the login keychain, not in this repo or in plain-text files. The `secret` command reads and stores them for the scripts here: `secret get|exists|set <service>`. `secret set` prompts for the value, so it never ends up in your shell history. rclone's config is encrypted with a password from the `rclone-config` item, and setup lists encrypting it as a to-do if it isn't.

## Adding a host

Create `modules/hosts/<name>/default.nix`, setting every option declared in [modules/host-options.nix](modules/host-options.nix), then run `./setup.sh <name>`.
