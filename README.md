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

3. Set up Tailscale: create an account at [tailscale.com](https://tailscale.com), ensure that Tailscale is installed on your laptop and sign in, then create a one-time auth key for the server: admin console → Settings → Keys → Generate auth key. For non-interactive runs, export `TAILSCALE_AUTHKEY` before running `setup.sh`; otherwise it will prompt.

4. SSH back in with agent forwarding (`-A`) and run the dotfiles setup. Agent forwarding allows cloning private repos (e.g. openclaw-workspace) using your local SSH key:
   ```sh
   ssh -A root@<server-ip>
   nix-shell -p git tmux --command tmux # use tmux to keep session alive as rebuild locks SSH to Tailscale only
   git clone https://github.com/thomasschafer/dotfiles.git ~/Development/dotfiles
   cd ~/Development/dotfiles && ./setup.sh nix-server
   ```
   This creates the non-root user with SSH keys configured, installs all packages, and sets up home-manager. It will prompt you to set a password for the non-root user (required for sudo), and for the Tailscale auth key from the previous step. It also copies `/etc/nixos/hardware-configuration.nix` to the repo, which you should commit.

   Note: The first run builds Helix from source which takes several minutes. If home-manager times out, just run `./setup.sh nix-server` again - it will skip already-completed steps.

5. SSH in as the non-root user using the Tailscale IP printed at the end of setup (username is configured in `modules/hosts/<hostname>/default.nix`). You can also retrieve it later with `tailscale ip -4` on the server.
   ```sh
   ssh <username>@<tailscale-ip>
   ```

### Tailscale setup

After deploy:
1. Approve exit node: Tailscale admin console → Machines → nix-server → Edit route settings → "Use as exit node"
2. Phone: install Tailscale app, sign in, select nix-server as exit node when desired

**Notes:**
- After setup, disable node key expiry on the server: admin console → Machines → nix-server → Edit → Disable key expiry. Without this, the node key expires after 180 days and the server silently drops off the tailnet.
- SSH is locked to the Tailscale interface only — the public IP no longer accepts SSH
- `setup.sh` checks `tailscale status` after rebuild and exits non-zero if Tailscale is unhealthy; keep the session open until it is online
- Escape hatch: if locked out, use Hetzner web console (VNC)
- If using Hetzner Cloud's firewall feature, allow inbound UDP 41641 for direct connections (otherwise Tailscale falls back to relays)

### OpenClaw setup

The setup script automatically:
- Clones `openclaw-workspace` to `~/Development/openclaw-workspace` and symlinks it to `~/.openclaw/workspace`
- Symlinks `~/.openclaw/cron/jobs.json` to `openclaw-workspace/config/cron-jobs.json`
- Symlinks `~/.openclaw/openclaw.json` to `dotfiles/openclaw/openclaw.json` (config lives in this repo)
- Generates a gateway token if one doesn't exist

After running the setup script:

1. Add Telegram bot: `openclaw channels login telegram` (enter token from @BotFather)
2. Approve contacts: `openclaw pairing list telegram`, then `openclaw pairing approve telegram <code>`
3. Access dashboard: `ssh -L 18789:127.0.0.1:18789 <username>@<tailscale-ip>`, then `http://127.0.0.1:18789/?token=<gateway-token>` (token is in `~/.openclaw/gateway-token.env`)

Optionally run `openclaw security audit` to verify config.

<details>
<summary>Troubleshooting</summary>

```sh
# Check gateway status
systemctl --user status openclaw-gateway

# View logs
tail -f /tmp/openclaw/openclaw-gateway.log

# Restart gateway
systemctl --user restart openclaw-gateway
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
