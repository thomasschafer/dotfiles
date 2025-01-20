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

# Zsh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=$HOME/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

# Haskell
[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env"
export PATH="$HOME/.local/bin:$PATH"

# LLVM
export PATH="$(brew --prefix)/opt/llvm/bin:$PATH"

# Helix
unset TMUX # Temporary solution until https://github.com/helix-editor/helix/issues/8715 is fixed
