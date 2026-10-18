# shellcheck shell=bash
# Shared helpers for the dependabot-review scripts. Source, don't execute.

lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$lib_dir/config.sh"

DEPENDABOT_AUTHOR="app/dependabot"

# Usage: review_marker <sha>
# Hidden marker on every comment this job posts, so a PR revision is reviewed once per
# mode. Dry-run reviews have their own marker, so going live re-reviews those revisions.
review_marker() {
    local mode=live
    [ "$DRY_RUN" = true ] && mode=dry-run
    printf '<!-- dependabot-review:%s:sha=%s -->' "$mode" "$1"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
    done
}

# Usage: read_secret <service>
read_secret() {
    local service="$1" value
    value=$(security find-generic-password -s "$service" -w 2>/dev/null) ||
        die "no keychain item for service '$service' (see README)"
    [ -n "$value" ] || die "secret '$service' is empty"
    printf '%s' "$value"
}

github_owner() {
    local owner
    owner=$(gh api user --jq .login) || die "could not determine GitHub user from gh"
    [ -n "$owner" ] || die "gh returned an empty login"
    printf '%s\n' "$owner"
}

# Usage: list_owned_repos <owner> <archived|active>
# Prints one "owner/name" per line. Excludes forks and anything not owned by <owner>.
list_owned_repos() {
    local owner="$1" which="$2" archived_flag
    case "$which" in
        archived) archived_flag=true ;;
        active) archived_flag=false ;;
        *) die "list_owned_repos: expected archived|active, got '$which'" ;;
    esac
    gh repo list "$owner" --source --limit 1000 \
        --json nameWithOwner,isArchived,isFork,owner \
        --jq ".[] | select(.isArchived == $archived_flag and (.isFork | not) and .owner.login == \"$owner\") | .nameWithOwner"
}

# Usage: has_dependabot_config <owner/repo>
has_dependabot_config() {
    gh api "repos/$1/contents/.github/dependabot.yml" --silent 2>/dev/null
}

# Prints the in-scope repos: owned, non-fork, non-archived, with a dependabot.yml.
list_in_scope_repos() {
    local owner repo repos
    owner=$(github_owner)
    repos=$(list_owned_repos "$owner" active) || die "could not list repos for $owner"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        if has_dependabot_config "$repo"; then
            printf '%s\n' "$repo"
        fi
    done <<<"$repos"
}

# Usage: list_dependabot_prs <owner/repo>
# Prints a JSON array of open Dependabot PRs.
list_dependabot_prs() {
    gh pr list -R "$1" --author "$DEPENDABOT_AUTHOR" --state open --limit 200 \
        --json number,title,url,headRefName,headRefOid,labels
}

default_branch() {
    gh repo view "$1" --json defaultBranchRef --jq .defaultBranchRef.name
}

# Usage: required_checks <owner/repo> <branch>
# Prints required status check names, one per line, from both classic branch
# protection and rulesets. Prints nothing if none are required.
required_checks() {
    local repo="$1" branch="$2" classic rulesets
    classic=$(gh api "repos/$repo/branches/$branch" \
        --jq '.protection.required_status_checks.checks // [] | .[].context') ||
        die "could not read branch $branch of $repo"
    rulesets=$(gh api "repos/$repo/rules/branches/$branch" \
        --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context') ||
        die "could not read rulesets for $branch of $repo"
    printf '%s\n%s\n' "$classic" "$rulesets" | sed '/^$/d' | sort -u
}

# Usage: summarise_dependabot_title <title>
# "chore(deps): bump log from 0.4.28 to 0.4.29 in /cli" -> "log 0.4.28 to 0.4.29".
# Grouped titles are returned without the leading "Bump ".
summarise_dependabot_title() {
    local title="$1"
    local prefix_re='^[a-z]+(\([^)]*\))?: (.*)$'
    local single_re='^[Bb]ump ([^ ]+) from ([^ ]+) to ([^ ]+)'
    if [[ "$title" =~ $prefix_re ]]; then
        title="${BASH_REMATCH[2]}"
    fi
    if [[ "$title" =~ $single_re ]]; then
        printf '%s %s to %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    else
        title="${title#Bump }"
        printf '%s\n' "${title#bump }"
    fi
}

# Container VM. Only WORK_DIR is mounted, so containers can't see the rest of $HOME.

use_job_docker_config() {
    mkdir -p "$STATE_DIR/docker"
    [ -f "$STATE_DIR/docker/config.json" ] || echo '{}' >"$STATE_DIR/docker/config.json"
    export DOCKER_CONFIG="$STATE_DIR/docker"
}

colima_running() {
    colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1
}

start_colima() {
    mkdir -p "$WORK_DIR"
    colima start --profile "$COLIMA_PROFILE" --cpu 4 --memory 8 --disk 60 \
        --vm-type vz --mount-type virtiofs --mount "$WORK_DIR:w"
}

stop_colima() {
    colima stop --profile "$COLIMA_PROFILE" >/dev/null 2>&1 || log "Failed to stop colima"
}

# Date helpers. Support both BSD (macOS) and GNU date.

date_is_gnu() {
    date --version >/dev/null 2>&1
}

# Usage: local_datetime_to_epoch "YYYY-MM-DD HH:MM:SS"
local_datetime_to_epoch() {
    if date_is_gnu; then
        date -d "$1" +%s
    else
        date -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s
    fi
}

# Usage: days_ago_date <n>  -> YYYY-MM-DD in local time
days_ago_date() {
    if date_is_gnu; then
        date -d "$1 days ago" +%Y-%m-%d
    else
        date -v-"$1"d +%Y-%m-%d
    fi
}

# Usage: epoch_to_utc_rfc3339 <epoch>
epoch_to_utc_rfc3339() {
    if date_is_gnu; then
        date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
    else
        date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
    fi
}

# Epoch seconds of the most recent Friday 20:00 local time at or before now.
last_friday_20_epoch() {
    local now weekday days_back candidate
    now=$(date +%s)
    weekday=$(date +%u)
    days_back=$(((weekday - 5 + 7) % 7))
    candidate=$(local_datetime_to_epoch "$(days_ago_date "$days_back") 20:00:00")
    if [ "$candidate" -gt "$now" ]; then
        candidate=$(local_datetime_to_epoch "$(days_ago_date $((days_back + 7))) 20:00:00")
    fi
    printf '%s\n' "$candidate"
}

# Todoist. Requires TODOIST_TOKEN to be set by the caller.

TODOIST_API="https://api.todoist.com/api/v1"

todoist_api() {
    local method="$1" path="$2" body="${3:-}"
    [ -n "${TODOIST_TOKEN:-}" ] || die "TODOIST_TOKEN is not set"
    local args=(-fsS --max-time 30 -X "$method" -H "Authorization: Bearer $TODOIST_TOKEN")
    if [ -n "$body" ]; then
        args+=(-H "Content-Type: application/json" --data "$body")
    fi
    curl "${args[@]}" "$TODOIST_API$path"
}

# Usage: todoist_get_all <path-with-query>
# Follows cursor pagination and prints all results as one JSON array.
todoist_get_all() {
    local path="$1" cursor="" page all="[]" sep="?"
    [[ "$path" == *\?* ]] && sep="&"
    while :; do
        if [ -n "$cursor" ]; then
            page=$(todoist_api GET "$path${sep}limit=200&cursor=$cursor") || return 1
        else
            page=$(todoist_api GET "$path${sep}limit=200") || return 1
        fi
        all=$(jq -n --argjson a "$all" --argjson p "$page" '$a + $p.results')
        cursor=$(jq -r '.next_cursor // empty' <<<"$page")
        [ -n "$cursor" ] || break
    done
    printf '%s\n' "$all"
}

# Fails loudly if a configured label does not exist, rather than letting the API create it.
todoist_check_labels() {
    local labels name
    labels=$(todoist_get_all "/labels") || die "could not list Todoist labels"
    for name in "$TODOIST_FIX_LABEL" "$TODOIST_CHORE_LABEL"; do
        jq -e --arg n "$name" 'any(.[]; .name == $n)' <<<"$labels" >/dev/null ||
            die "Todoist label '$name' not found"
    done
}

# Usage: todoist_open_task_mentioning <text>
# Succeeds if an open task in the Dependabot section has <text> in its title or description.
todoist_open_task_mentioning() {
    local tasks
    tasks=$(todoist_get_all "/tasks?project_id=$TODOIST_PROJECT_ID&section_id=$TODOIST_SECTION_ID") ||
        die "could not list Todoist tasks"
    jq -e --arg t "$1" 'any(.[]; (.content | contains($t)) or ((.description // "") | contains($t)))' \
        <<<"$tasks" >/dev/null
}

# Usage: todoist_flag <kind> <title> <description> [dedupe-key]
# kind: urgent | broken | review | config | unhealthy
# Skips creation if an open task already mentions dedupe-key (defaults to the title).
todoist_flag() {
    local kind="$1" title="$2" description="$3" dedupe_key="${4:-$2}"
    local label priority due_field due_value

    # API priorities are inverted: 4 is p1, 1 is p4.
    case "$kind" in
        urgent)
            label="$TODOIST_CHORE_LABEL" priority=4 due_field=due_datetime
            due_value=$(epoch_to_utc_rfc3339 $(($(date +%s) + 600)))
            ;;
        broken) label="$TODOIST_FIX_LABEL" priority=2 due_field=due_string due_value=tomorrow ;;
        review) label="$TODOIST_CHORE_LABEL" priority=2 due_field=due_string due_value=tomorrow ;;
        config) label="$TODOIST_CHORE_LABEL" priority=1 due_field=due_string due_value=tomorrow ;;
        unhealthy) label="$TODOIST_FIX_LABEL" priority=3 due_field=due_string due_value=today ;;
        *) die "todoist_flag: unknown kind '$kind'" ;;
    esac
    [ -n "$due_value" ] || die "todoist_flag: could not compute due date"

    if todoist_open_task_mentioning "$dedupe_key"; then
        log "Todoist: open task already exists for $dedupe_key, not re-flagging"
        return 0
    fi

    local body
    body=$(jq -n \
        --arg content "$title" --arg description "$description" \
        --arg project "$TODOIST_PROJECT_ID" --arg section "$TODOIST_SECTION_ID" \
        --arg label "$label" --argjson priority "$priority" \
        --arg due_field "$due_field" --arg due_value "$due_value" \
        '{content: $content, description: $description, project_id: $project,
          section_id: $section, labels: [$label], priority: $priority}
         + {($due_field): $due_value}')
    todoist_api POST "/tasks" "$body" >/dev/null || die "failed to create Todoist task: $title"
    log "Todoist: created $kind task: $title"
}
