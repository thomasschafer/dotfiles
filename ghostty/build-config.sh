#!/usr/bin/env bash

set -euo pipefail

# Renders ghostty/config.template into something Ghostty can parse.
#
# Ghostty only treats `#` as a comment when it starts a line, so the template's
# trailing `##` annotations have to be stripped first. Both the Nix derivation
# in modules/home.nix and manual installs on non-Nix machines render through
# here so the two can't drift apart.

USAGE="Usage: $(basename "$0") <template> [output]"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "$USAGE" >&2
    exit 1
fi

template="$1"

if [ ! -f "$template" ]; then
    echo "Error: template not found: $template" >&2
    exit 1
fi

render() {
    sed 's/[[:space:]]*##.*$//' "$template"
}

if [ "$#" -eq 2 ]; then
    # Render via a temporary file so a failure part-way through leaves the
    # existing config intact rather than truncating it.
    output="$2"
    mkdir -p "$(dirname "$output")"
    temporary_path="$(mktemp "${output}.XXXXXX")"
    trap 'rm -f "$temporary_path"' EXIT
    render > "$temporary_path"
    mv "$temporary_path" "$output"
    trap - EXIT
else
    render
fi
