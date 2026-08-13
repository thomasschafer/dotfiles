#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
codex_home="${CODEX_HOME:-$HOME/.codex}"
generated_codex_instructions="$state_home/dotfiles/ai-guidance/AGENTS.md"

link_file() {
    local source_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "$target_path")"
    if [[ -e "$target_path" && ! -L "$target_path" ]]; then
        echo "Error: refusing to replace non-symlink $target_path" >&2
        return 1
    fi

    ln -sfn "$source_path" "$target_path"
}

render_codex_instructions() {
    local output_path="$1"
    local temporary_path

    mkdir -p "$(dirname "$output_path")"
    temporary_path="$(mktemp "${output_path}.XXXXXX")"
    {
        cat "$repo_root/agents/shared.md"
        if [[ -s "$repo_root/codex/instructions.md" ]]; then
            printf '\n'
            cat "$repo_root/codex/instructions.md"
        fi
    } > "$temporary_path"
    mv "$temporary_path" "$output_path"
}

render_codex_instructions "$generated_codex_instructions"
link_file "$repo_root/agents/shared.md" "$HOME/.config/ai/instructions.md"
link_file "$repo_root/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_file "$generated_codex_instructions" "$codex_home/AGENTS.md"
link_file "$repo_root/agents/shared.md" "$HOME/.cursor/rules/coding-standards.mdc"
