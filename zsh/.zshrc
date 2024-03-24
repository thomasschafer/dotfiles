if [[ -f ~/.zshrc.private ]]; then
    source ~/.zshrc.private
fi

# Prompt
autoload -Uz vcs_info
precmd() { vcs_info }
setopt prompt_subst
zstyle ':vcs_info:git:*' formats '(%F{cyan}%b%f) '
PROMPT='> %F{green}%1~%f ${vcs_info_msg_0_}$ '

# Neovim
export EDITOR=nvim
export VISUAL="$EDITOR"
alias vi="nvim"
alias nv="nvim ."

# git autocompletion
autoload -Uz compinit && compinit

# LazyGit
alias lg=lazygit
alias ldr=lazydocker

# ZSh history
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=~/.zhistory
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY

[ -f "/Users/tschafer/.ghcup/env" ] && . "/Users/tschafer/.ghcup/env" # ghcup-env
