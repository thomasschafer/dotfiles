#!/usr/bin/env bash
version_output=$(golangci-lint version 2>&1)
if [[ "$version_output" =~ ^golangci-lint\ has\ version\ v?2\. ]]; then
    # v2: use new output format
    exec golangci-lint run --output.json.path stdout --show-stats=false --issues-exit-code=1 "$@"
else
    # v1: use old format
    exec golangci-lint run --out-format json --issues-exit-code=1 "$@"
fi
