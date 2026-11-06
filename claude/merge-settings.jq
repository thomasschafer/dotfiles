# Merges overrides (the second input) into a settings file an agent also writes to (the first),
# such as settings-overrides.json into Claude Code's settings.json, or codex/hooks-overrides.json
# into Codex's hooks.json. Objects merge recursively and the overrides win for other values,
# except that arrays are combined: entries the agent added (such as "always allow" permission
# rules, or other tools' hooks) are kept, and override entries missing from them are appended.
# So removing an entry from the overrides doesn't remove it from the file; delete it there too.
def merge($base; $override):
  if ($base | type) == "object" and ($override | type) == "object" then
    reduce ($override | keys_unsorted[]) as $key ($base; .[$key] = merge($base[$key]; $override[$key]))
  elif ($base | type) == "array" and ($override | type) == "array" then
    $base + [$override[] | select(. as $entry | $base | index([$entry]) | not)]
  else
    $override
  end;

merge(.[0]; .[1])
