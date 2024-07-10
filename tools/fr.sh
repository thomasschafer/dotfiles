#!/bin/bash

if [ "$#" -ne 2 ]; then
    SCRIPT_BASENAME="$(basename "$0")"
    echo "Usage: $SCRIPT_BASENAME <BEFORE> <AFTER>"
    exit 1
fi

BEFORE=$1
AFTER=$2

rg -l "$BEFORE" | xargs -I {} sd "$BEFORE" "$AFTER" {}
