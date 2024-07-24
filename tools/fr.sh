#!/bin/bash

USAGE="Usage: $(basename "$0") [-F|--fixed-strings] [-p|--preview] <BEFORE> [AFTER]"

SHARED_FLAGS=""
PREVIEW=false

while [[ "$1" =~ ^- ]]; do
    case $1 in
        -F|--fixed-strings )
            SHARED_FLAGS="-F"
            shift
            ;;
        -p|--preview )
            PREVIEW=true
            shift
            ;;
        -* )
            echo "$USAGE"
            exit 1
            ;;
    esac
done

if [ "$PREVIEW" = true ]; then
    if [ "$#" -ne 1 ]; then
        echo "$USAGE"
        exit 1
    fi

    BEFORE=$1

    rg $SHARED_FLAGS "$BEFORE"
else
    if [ "$#" -ne 2 ]; then
        echo "$USAGE"
        exit 1
    fi

    BEFORE=$1
    AFTER=$2

    rg $SHARED_FLAGS -l "$BEFORE" | xargs -I {} sd $SHARED_FLAGS "$BEFORE" "$AFTER" {}
fi

