# Work-specific config
if [[ -f $HOME/.zshrc.private ]]; then
    source $HOME/.zshrc.private
fi

# Treat / as a word delimiter
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# Prompt
autoload -Uz vcs_info
precmd() { vcs_info }
setopt prompt_subst
zstyle ':vcs_info:git:*' formats '(%F{cyan}%b%f) '
if [[ "$(uname)" == "Darwin" ]]; then
    PROMPT='%B%(?.%F{grey}.%F{red})%?%f%b | %F{green}%1~%f ${vcs_info_msg_0_}$ '
else
    PROMPT='%B%(?.%F{grey}.%F{red})%?%f%b | %F{magenta}%m%f | %F{green}%1~%f ${vcs_info_msg_0_}$ '
fi

# Helix keymap (zshelix)
if [[ -f $HOME/Development/zshelix/zshelix.plugin.zsh ]]; then
    ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#b8c0e0\a'
    ZHM_CURSOR_INSERT=$'\e[2 q\e]12;#f4dbd6\a'
    ZHM_CURSOR_SELECT=$'\e[2 q\e]12;#f5a97f\a'
    ZSH_HELIX_SYSTEM_CLIPBOARD=1
    source $HOME/Development/zshelix/zshelix.plugin.zsh
fi

# Note: compinit is run by Nix's /etc/zshrc. If we stop using Nix, add back:
# autoload -Uz compinit && compinit -C

# Aliases and editor config
export EDITOR=hx
export VISUAL="$EDITOR"
alias nv=nvim
alias c=claude
alias z=zed
alias y=yazi
alias s=scooter
alias lg=lazygit
alias ldr=lazydocker

# Platform-specific aliases
if [[ "$(uname)" == "Darwin" ]]; then
    alias dp="cd $HOME/Development/dotfiles/ && sudo darwin-rebuild switch --flake .#personal && cd -"
    alias dw="cd $HOME/Development/dotfiles/ && sudo darwin-rebuild switch --flake .#work && cd -"
else
    alias ns="cd $HOME/Development/dotfiles/ && sudo nixos-rebuild switch --flake .#nix-server --impure && cd -"

    openclaw() {
        # TODO: once https://github.com/openclaw/nix-openclaw/issues/45 is fixed, remove hasown workaround
        local gw_path hasown_path
        gw_path=$(dirname $(dirname $(readlink -f $(command which openclaw))))
        hasown_path=$(find "$gw_path/lib/openclaw/node_modules/.pnpm" -maxdepth 2 -type d -name "hasown@*" 2>/dev/null | head -1)

        # TODO: once https://github.com/openclaw/nix-openclaw/issues/18 is fixed, remove templates workaround
        local templates_dir="$HOME/.openclaw/docs/reference/templates"
        if [[ ! -d "$templates_dir" ]]; then
            echo "Fetching openclaw templates..." >&2
            mkdir -p "$templates_dir"
            for t in AGENTS.md BOOT.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md; do
                curl -sL "https://raw.githubusercontent.com/openclaw/openclaw/main/docs/reference/templates/$t" -o "$templates_dir/$t"
            done
        fi

        # Run from ~/.openclaw so it finds templates via cwd (part of #18 workaround)
        (
            cd "$HOME/.openclaw"
            if [[ -n "$hasown_path" ]]; then
                NODE_PATH="$hasown_path/node_modules" command openclaw "$@"
            else
                command openclaw "$@"
            fi
        )
    }
fi

# Zsh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=$HOME/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

# Rancher desktop (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
    export DOCKER_HOST="unix://$HOME/.rd/docker.sock"
    export PATH="$HOME/.rd/bin:$PATH"
fi

# Nix helpers
alias NIX_CLEAN="sudo nix-collect-garbage -d"
alias NIX_ORPHANS="sudo nix store gc && sudo nix store optimise"
alias NIX_WIPE="sudo nix profile wipe-history"
alias NIX_SYSTEM_CLEAN="NIX_CLEAN && NIX_ORPHANS && NIX_WIPE"

# Path
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"  # Nix - TODO is there a better way of doing this?
export PATH="$HOME/go/bin:$PATH"

# direnv
eval "$(direnv hook zsh)"
