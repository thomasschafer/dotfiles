# dotfiles

## macOS

```sh
git clone git@github.com:thomasschafer/dotfiles.git ~/Development/dotfiles
cd ~/Development/dotfiles
./setup.sh personal  # or ./setup.sh work
```

## NixOS server

1. Provision a server with Debian (or any OS compatible with [nixos-infect](https://github.com/elitak/nixos-infect)). Add your SSH key during provisioning, and ensure the same key is in `modules/hosts/<hostname>/default.nix`.

2. SSH in and run nixos-infect (use tmux in case connection drops):
   ```sh
   ssh root@<server-ip>
   apt update && apt install -y tmux && tmux
   curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | NO_SWAP=1 NIX_CHANNEL=nixos-24.05 bash -x
   ```
   The server will reboot automatically.

3. SSH back in and run the dotfiles setup:
   ```sh
   ssh root@<server-ip>
   nix-shell -p git
   git clone https://github.com/thomasschafer/dotfiles.git ~/Development/dotfiles
   cd ~/Development/dotfiles && ./setup.sh nix-server
   ```
   This creates the non-root user with SSH keys configured, installs all packages, and sets up home-manager. It will prompt you to set a password for the non-root user (required for sudo). It also copies `/etc/nixos/hardware-configuration.nix` to the repo, which you should commit.

   Note: The first run builds Helix from source which takes several minutes. If home-manager times out, just run `./setup.sh nix-server` again - it will skip already-completed steps.

4. SSH in as the non-root user:
   ```sh
   ssh tomschafer@<server-ip>
   ```

### OpenClaw setup

After `./setup.sh nix-server`:

1. Run `openclaw onboard`
2. Add Telegram bot: `openclaw channels login telegram` (enter token from @BotFather)
3. Run `openclaw security audit` to verify config
4. Approve contacts: `openclaw pairing list telegram`, then `openclaw pairing approve telegram <code>`
5. Access dashboard: `ssh -L 18789:127.0.0.1:18789 tomschafer@<server-ip>`, then `http://127.0.0.1:18789/?token=<gateway-token>` (get the token from `~/.openclaw/gateway-token.env`)

<details>
<summary>Troubleshooting</summary>

```sh
# Check gateway status
systemctl --user status openclaw-gateway

# View logs
tail -f /tmp/openclaw/openclaw-gateway.log

# Restart gateway
systemctl --user restart openclaw-gateway

# Check channel status
openclaw channels status
```

</details>

#### GitHub permissions for OpenClaw

To restrict OpenClaw to only pushing branches and creating PRs:

1. Create a fine-grained PAT: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - **Repository access:** "Only select repositories" → select repos
   - **Permissions:** `Contents: Read and write`, `Pull requests: Read and write`, everything else "No access"
2. Set up branch protection on each repo: Settings → Branches → Add rule → protect `main`
3. On nix-server:
   ```sh
   git config --global user.email "YOUR_EMAIL"
   git config --global user.name "YOUR_NAME"
   mkdir -p ~/.openclaw/credentials && (umask 077 && echo "TOKEN" > ~/.openclaw/credentials/github-token)
   gh auth login --with-token < ~/.openclaw/credentials/github-token
   gh auth setup-git
   ```
