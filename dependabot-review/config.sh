# shellcheck shell=bash
# shellcheck disable=SC2034  # Variables are used by the scripts that source this.
# Settings for the dependabot-review scripts. Sourced by lib.sh.

# While true, the weekly job only comments its verdict and creates Todoist tasks:
# it never merges, pushes or opens PRs.
DRY_RUN=false

# Pinned explicitly so the job never silently changes model.
CLAUDE_MODEL="claude-opus-5-5"
MAX_TURNS_PER_PR=60
MAX_BUDGET_USD_PER_PR=5

COOLDOWN_DAYS=5
STALE_AFTER_DAYS=10
LOG_RETENTION_DAYS=28
# Longest wait for CI after pushing a fix or split commit.
CI_TIMEOUT_MINUTES=45

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dependabot-review"
# Only this directory is mounted into the container VM.
WORK_DIR="$STATE_DIR/work"

COLIMA_PROFILE="dependabot-review"
DOCKER_CONTEXT="colima-$COLIMA_PROFILE"

# Keychain service names.
GITHUB_TOKEN_SECRET="dependabot-review-github"
TODOIST_TOKEN_SECRET="dependabot-review-todoist"

NEEDS_TOM_LABEL="needs-tom"

TODOIST_PROJECT_ID="6hCFGfFgFqm8V7Cf"
TODOIST_SECTION_ID="6hmwVfmp8xMx9qJ7"
TODOIST_FIX_LABEL="Fix 💻"
TODOIST_CHORE_LABEL="Chore 💻"
