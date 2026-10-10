#!/bin/sh
set -eu

herdr="${HERDR_BIN_PATH:-herdr}"
workspace_label="Development"
workspace_dir="$HOME/Development"
tab_label="caf"

if pgrep -fx 'caffeinate -is' >/dev/null; then
  exit 0
fi

ws=$("$herdr" workspace list | jq -r --arg label "$workspace_label" \
  'first(.result.workspaces[] | select(.label == $label) | .workspace_id) // empty')
if [ -z "$ws" ]; then
  ws=$("$herdr" workspace create --label "$workspace_label" --cwd "$workspace_dir" --no-focus \
    | jq -er '.result.workspace.workspace_id')
fi

stale=$("$herdr" tab list --workspace "$ws" | jq -r --arg label "$tab_label" \
  '.result.tabs[] | select(.label == $label) | .tab_id')
for tab in $stale; do
  "$herdr" tab close "$tab" >/dev/null
done

pane=$("$herdr" tab create --workspace "$ws" --label "$tab_label" --cwd "$workspace_dir" --no-focus \
  | jq -er '.result.root_pane.pane_id')
# Input sent before the shell draws its prompt is echoed twice.
if ! "$herdr" pane wait-output "$pane" --regex '\$\s*$' --timeout 5000 >/dev/null; then
  echo "caffeinate: no shell prompt in pane $pane after 5s, running anyway" >&2
fi
"$herdr" pane run "$pane" "caffeinate -is"
