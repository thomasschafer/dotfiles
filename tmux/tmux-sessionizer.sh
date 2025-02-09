#!/bin/bash

# https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/scripts/tmux-sessionizer

if [[ $# -eq 1 ]]; then
    selected=$1
else
    dirs=()
    for d in "$HOME/Development" "$HOME/Development/Snyk"; do
        [ -d "$d" ] && dirs+=("$d")
    done
    selected=$(fd -d 1 --type d --type l . "${dirs[@]}" | sed 's:/*$::' | fzf --layout reverse)
fi

if [[ -z $selected ]]; then
    exit 0
fi

selected_name=$(basename "$selected" | tr . _)
tmux_running=$(pgrep tmux)

create_session() {
    tmux new-session -ds $1 -c $2
    tmux split-window -h -t $1 -c $2
    tmux send-keys -t $1:0.1 'hx' Enter
}

if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    create_session $selected_name $selected
    tmux attach-session -t $selected_name
    exit 0
fi

if ! tmux has-session -t=$selected_name 2> /dev/null; then
    create_session $selected_name $selected
fi

tmux switch-client -t $selected_name
