# dotfiles

## macOS

```sh
git clone git@github.com:thomasschafer/dotfiles.git ~/Development/dotfiles
cd ~/Development/dotfiles
./setup.sh personal  # or ./setup.sh work
```

## NixOS server

1. Provision a server with Debian (or any OS compatible with [nixos-infect](https://github.com/elitak/nixos-infect))

2. Copy your SSH key to root (from your local machine):
   ```sh
   ssh-copy-id root@<server-ip>
   ```

3. SSH in and run nixos-infect (use tmux in case connection drops):
   ```sh
   ssh root@<server-ip>
   apt update && apt install -y tmux && tmux
   curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | NO_SWAP=1 NIX_CHANNEL=nixos-24.05 bash -x
   ```
   The server will reboot automatically.

4. SSH back in and set the non-root user password first (required for sudo after setup reconfigures SSH):
   ```sh
   ssh root@<server-ip>
   useradd -m tomschafer
   passwd tomschafer
   ```

5. Clone and run the dotfiles setup:
   ```sh
   nix-shell -p git
   git clone https://github.com/thomasschafer/dotfiles.git ~/Development/dotfiles
   cd ~/Development/dotfiles && ./setup.sh nix-server
   ```
   This creates the non-root user with SSH keys configured, installs all packages, and sets up home-manager. It also adds `/etc/nixos/hardware-configuration.nix` to this repo, which you should commit.

   Note: The first run builds Helix from source which takes several minutes. If home-manager times out, just run `./setup.sh nix-server` again - it will skip already-completed steps.

6. SSH in as the non-root user:
   ```sh
   ssh tomschafer@<server-ip>
   ```
