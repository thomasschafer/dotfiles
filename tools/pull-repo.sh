#!/usr/bin/env bash
# Fast-forwards one of the checkouts the dotfiles build from (see cloneRepo in
# modules/home.nix) to its upstream, so the build steps after it pick up new commits.
# Only pulls when that can't disturb local work: the checkout must be on its tracked branch,
# with no changes to tracked files, no rebase or merge in progress, and no commits that
# aren't upstream. Otherwise it says why it didn't pull, on stderr and in the warnings
# file for setup.sh, and exits 0 so the switch carries on with the checkout as it is.
#
# Usage: pull-repo.sh <checkout> <branch> <submodules> <warnings file>
#   branch: the branch to track, or "" for the remote's default branch
#   submodules: 1 to update the checkout's submodules after pulling, otherwise 0

set -euo pipefail

if [ $# -ne 4 ]; then
    echo "Usage: $0 <checkout> <branch> <submodules> <warnings file>" >&2
    exit 1
fi
repo_dir="$1"
branch="$2"
submodules="$3"
warnings_file="$4"
case "$submodules" in
    0 | 1) ;;
    *)
        echo "$0: submodules must be 0 or 1, not '$submodules'" >&2
        exit 1
        ;;
esac
name="$(basename "$repo_dir")"
fetch_timeout=120

# From coreutils, which macOS lacks; the wrapper in modules/home.nix puts it on PATH.
command -v timeout >/dev/null || {
    echo "$0: timeout isn't on PATH" >&2
    exit 1
}

skip() {
    printf 'warning: not pulling %s: %s\n' "$name" "$1" >&2
    mkdir -p "$(dirname "$warnings_file")"
    printf 'not pulling %s: %s\n' "$name" "$1" >>"$warnings_file"
    exit 0
}

[ -e "$repo_dir/.git" ] || skip "$repo_dir isn't a git checkout"
cd "$repo_dir"
# Fail rather than wait for credentials nobody is there to type.
export GIT_TERMINAL_PROMPT=0

git_dir="$(git rev-parse --git-dir)"
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    [ ! -e "$git_dir/$marker" ] || skip "a rebase, merge, cherry-pick, revert or bisect is in progress"
done

current="$(git symbolic-ref --quiet --short HEAD)" || skip "HEAD is detached"
if [ -z "$branch" ]; then
    default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)" \
        || skip "origin's default branch isn't known; set it with: git -C $repo_dir remote set-head origin --auto"
    branch="${default#origin/}"
fi
[ "$current" = "$branch" ] || skip "it's on $current rather than $branch"

upstream="$(git rev-parse --quiet --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
    || skip "$branch has no upstream branch"
git diff --quiet HEAD || skip "it has uncommitted changes to tracked files"

remote="${upstream%%/*}"
timeout "$fetch_timeout" git fetch --quiet --no-recurse-submodules "$remote" \
    || skip "fetching $remote failed or took over ${fetch_timeout}s"

ahead="$(git rev-list --count "$upstream..HEAD")"
[ "$ahead" = 0 ] || skip "$branch has $ahead commit(s) that aren't on $upstream"

before="$(git rev-parse HEAD)"
git merge --ff-only --quiet "$upstream" >/dev/null || skip "fast-forwarding to $upstream failed; git said why in the switch's output"
after="$(git rev-parse HEAD)"
[ "$before" != "$after" ] || exit 0

if [ "$submodules" = 1 ] \
    && ! timeout "$fetch_timeout" git submodule update --init --recursive --quiet; then
    # Back to where it was, so the build doesn't mix new code with old submodules.
    git reset --quiet --keep "$before"
    skip "updating its submodules failed, so it's back at ${before:0:12}; git said why in the switch's output"
fi

echo "Pulled $name: ${before:0:12}..${after:0:12} ($(git rev-list --count "$before..$after") new commit(s))"
