# Work-specific config
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
PROMPT='%B%(?.%F{grey}.%F{red})%?%f%b | %F{green}%1~%f ${vcs_info_msg_0_}$ '

# Helix keymap
ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#b8c0e0\a'
ZHM_CURSOR_INSERT=$'\e[2 q\e]12;#f4dbd6\a'
ZHM_CURSOR_SELECT=$'\e[2 q\e]12;#f5a97f\a'
ZSH_HELIX_SYSTEM_CLIPBOARD=1
source $HOME/Development/zshelix/zshelix.plugin.zsh

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
alias dp="cd $HOME/Development/dotfiles/ && sudo darwin-rebuild switch --flake .#personal && cd -"
alias dw="cd $HOME/Development/dotfiles/ && sudo darwin-rebuild switch --flake .#work && cd -"

# Zsh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=$HOME/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

# Rancher desktop
export DOCKER_HOST="unix://$HOME/.rd/docker.sock"
### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/thomasschafer/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Nix helpers
alias NIX_CLEAN="sudo nix-collect-garbage -d"
alias NIX_ORPHANS="sudo nix store gc && sudo nix store optimise"
alias NIX_WIPE="sudo nix profile wipe-history"
alias NIX_SYSTEM_CLEAN="NIX_CLEAN && NIX_ORPHANS && NIX_WIPE"

# Path
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.rd/bin:$PATH"
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"  # Nix - TODO is there a better way of doing this?
export PATH="$HOME/go/bin:$PATH"

# direnv
eval "$(direnv hook zsh)"
