#!/usr/bin/env bash
# Deploys one of the apps declared with deploy.apps in modules/deploy.nix: builds a committed
# revision in a fresh clone, points `current` at it and restarts the app's launchd agents.
# Working-tree edits never go live, and a failed build leaves the running release alone.
#
# Expects DEPLOY_CONFIG (the apps, as JSON) and DEPLOYS_DIR in the environment, which the
# `deploy` wrapper sets.

set -euo pipefail

die() {
    echo "deploy: $*" >&2
    exit 1
}

[ -n "${DEPLOY_CONFIG:-}" ] && [ -n "${DEPLOYS_DIR:-}" ] || die "run this through the deploy command"
apps=$(jq -r 'keys | join(", ")' "$DEPLOY_CONFIG")

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: deploy <app> [ref]   (app: one of $apps; ref defaults to main)" >&2
    exit 1
fi
app="$1"
ref="${2:-main}"

jq -e --arg app "$app" 'has($app)' "$DEPLOY_CONFIG" >/dev/null || die "unknown app '$app' (one of $apps)"
field() {
    jq -r --arg app "$app" ".[\$app].$1" "$DEPLOY_CONFIG"
}
repo=$(field repo)
build=$(field build)
build_path=$(field path)
labels=()
while IFS= read -r label; do
    labels+=("$label")
done < <(jq -r --arg app "$app" '.[$app].labels[]' "$DEPLOY_CONFIG")

[ -d "$repo/.git" ] || die "no git repo at $repo"
sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || die "no commit '$ref' in $repo"

root="$DEPLOYS_DIR/$app"
releases="$root/releases"
mkdir -p "$releases"
lock="$root/lock"
mkdir "$lock" 2>/dev/null || die "another deploy of $app is running (or one was killed; remove $lock)"
staging=""
cleanup() {
    [ -z "$staging" ] || rm -rf "$staging"
    rmdir "$lock"
}
trap cleanup EXIT

release="$releases/$(date +%Y%m%d-%H%M%S)-${sha:0:12}"
staging="$release.partial"
echo "deploy: building $app at ${sha:0:12} ($(git -C "$repo" log -1 --format=%s "$sha"))"
# A clone rather than an export, as builds may read the commit. Local clones hardlink objects.
git clone --quiet --no-checkout "$repo" "$staging"
git -C "$staging" checkout --quiet --detach "$sha"
if ! (cd "$staging" && PATH="$build_path:$PATH" DEPLOY_DIR="$root" "$build"); then
    die "the build failed, so nothing changed"
fi
mv "$staging" "$release"
staging=""

# Replaces the symlink in one rename, so `current` always points at a complete release.
ln -s "$release" "$root/current.new"
/bin/mv -fh "$root/current.new" "$root/current"
echo "deploy: $app now runs ${sha:0:12}"

uid=$(id -u)
restarted=()
for label in "${labels[@]}"; do
    if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
        launchctl kickstart -k "gui/$uid/$label"
        restarted+=("$label")
    fi
done

# Keeps the previous release too, which processes that haven't restarted yet may still use.
find "$releases" -mindepth 1 -maxdepth 1 -type d -name '*.partial' -exec rm -rf {} +
old=$(find "$releases" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +3)
if [ -n "$old" ]; then
    while IFS= read -r dir; do
        rm -rf "$dir"
    done <<<"$old"
fi

if [ ${#restarted[@]} -eq 0 ]; then
    echo "deploy: no agents of $app are loaded, so none were restarted"
    exit 0
fi
sleep 5
failed=0
for label in "${restarted[@]}"; do
    if launchctl print "gui/$uid/$label" | grep -q '^\s*state = running'; then
        echo "deploy: $label restarted"
    else
        failed=1
        echo "deploy: $label isn't running; check its log, or roll back with \`deploy $app <older ref>\`" >&2
    fi
done
exit "$failed"
