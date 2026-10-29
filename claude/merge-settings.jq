# Merges settings-overrides.json (the second input) into Claude Code's settings.json (the first).
# Objects merge recursively and the overrides win for other values, except that arrays are
# combined: entries Claude Code added (such as "always allow" permission rules) are kept, and
# override entries missing from them are appended. So removing an entry from the overrides
# doesn't remove it from settings.json; delete it there too.
def merge($base; $override):
  if ($base | type) == "object" and ($override | type) == "object" then
    reduce ($override | keys_unsorted[]) as $key ($base; .[$key] = merge($base[$key]; $override[$key]))
  elif ($base | type) == "array" and ($override | type) == "array" then
    $base + [$override[] | select(. as $entry | $base | index([$entry]) | not)]
  else
    $override
  end;

merge(.[0]; .[1])
