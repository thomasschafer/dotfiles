# Treat / as a word delimiter
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# Prompt
autoload -Uz vcs_info
precmd() { vcs_info }
setopt prompt_subst
zstyle ':vcs_info:git:*' formats '(%F{cyan}%b%f) '
PROMPT='%B%(?.%F{grey}.%F{red})%?%f%b | %F{green}%1~%f ${vcs_info_msg_0_}$ '

# Helix keymap (zshelix)
if [[ -f $HOME/Development/Personal/zshelix/zshelix.plugin.zsh ]]; then
    ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#b8c0e0\a'
    ZHM_CURSOR_INSERT=$'\e[2 q\e]12;#f4dbd6\a'
    ZHM_CURSOR_SELECT=$'\e[2 q\e]12;#f5a97f\a'
    ZSH_HELIX_SYSTEM_CLIPBOARD=1
    source $HOME/Development/Personal/zshelix/zshelix.plugin.zsh
fi

# Note: compinit is run by Nix's /etc/zshrc. If we stop using Nix, add back:
# autoload -Uz compinit && compinit -C

# Claude config
export CLAUDE_CODE_NO_FLICKER=1

# Aliases and editor config
export EDITOR=hx
export VISUAL="$EDITOR"
alias nv=nvim
alias c='claude --permission-mode auto'
alias cy='claude --dangerously-skip-permissions'
alias x='codex'
alias xa='codex --ask-for-approval on-request'
alias xy='codex --yolo'
alias o='opencode'
alias z=zed
alias y=yazi
alias s=scooter
alias lg=lazygit
alias h=herdr

# Only on machines managed by nix-darwin, as setup.sh would otherwise install Nix
if command -v darwin-rebuild &>/dev/null; then
    alias dp="$HOME/Development/Personal/dotfiles/setup.sh personal"
fi

# Zsh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=$HOME/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

# Nix helpers
alias NIX_CLEAN="sudo nix-collect-garbage -d"
alias NIX_ORPHANS="sudo nix store gc && sudo nix store optimise"
alias NIX_WIPE="sudo nix profile wipe-history"
alias NIX_SYSTEM_CLEAN="NIX_CLEAN && NIX_ORPHANS && NIX_WIPE"

# herdr vendors a Zig build that requires an exact toolchain version (see
# crates/ghostty-vt/build.rs in herdr); brew's versioned zig is kept off PATH
# so it doesn't shadow the newer default `zig`, so point ZIG at it directly.
if [[ -x /opt/homebrew/opt/zig@0.16/bin/zig ]]; then
    export ZIG=/opt/homebrew/opt/zig@0.16/bin/zig
fi

# Path
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"  # Nix - TODO is there a better way of doing this?
# Last, so tools installed with `go install` don't shadow anything else
export PATH="$PATH:$HOME/go/bin"

# Work-specific config
if [[ -f $HOME/.zshrc.private ]]; then
    source $HOME/.zshrc.private
fi

# direnv
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi

# mise
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi

# atuin
if command -v atuin &>/dev/null; then
    eval "$(atuin init zsh)"
fi

# Background apps that have stopped (Workshop, health-tracking)
if command -v agents-status &>/dev/null; then
    agents-status --quiet || true
fi
