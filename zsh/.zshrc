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
zstyle ':vcs_info:git:*' formats '(%F{#91d7e3}%b%f) '
PROMPT='> %F{#a6da95}%1~%f ${vcs_info_msg_0_}$ '

# Helix keymap
ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#b8c0e0\a'
ZHM_CURSOR_INSERT=$'\e[2 q\e]12;#f4dbd6\a'
ZHM_CURSOR_SELECT=$'\e[2 q\e]12;#f5a97f\a'
source $HOME/Development/zshelix/zshelix.plugin.zsh

# Git autocompletion
autoload -Uz compinit && compinit

# Aliases and editor config
export EDITOR=hx
export VISUAL="$EDITOR"
alias nv=nvim
alias c=code
alias z=zed
alias y=yazi
alias s=scooter
alias lg=lazygit
alias ldr=lazydocker
alias dp="cd $HOME/Development/dotfiles/nix/ && darwin-rebuild switch --flake .#personal && cd -"
alias dw="cd $HOME/Development/dotfiles/nix/ && darwin-rebuild switch --flake .#work && cd -"

# Zsh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=$HOME/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

export PATH="$HOME/.local/bin:$PATH"

# Nix - TODO is there a better way of doing this?
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"

