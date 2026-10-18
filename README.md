# dotfiles

## macOS

```sh
git clone git@github.com:thomasschafer/dotfiles.git ~/Development/Personal/dotfiles
cd ~/Development/Personal/dotfiles
./setup.sh personal
```

Re-run `setup.sh` (or `dp`) to apply changes. On hosts with `enableDependabotReview`, it also installs the weekly Dependabot review job and prompts you to log in to the Claude CLI and for its GitHub and Todoist tokens if they're missing. Create them first, as described in [dependabot-review/README.md](dependabot-review/README.md#setup), or skip the prompt and run `./dependabot-review/setup-secrets` later.

## Adding a host

Create `modules/hosts/<name>/default.nix`, setting every option declared in [modules/host-options.nix](modules/host-options.nix), then run `./setup.sh <name>`.
