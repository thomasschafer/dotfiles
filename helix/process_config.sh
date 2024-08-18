#!/bin/bash

set -e
set -o pipefail

source env/bin/activate

for arg in "$@"; do
    if [ "$arg" == "--install" ]; then
				python3 -m pip install toml
    fi
done

python3 process_config.py config.template.toml config.toml
deactivate

echo "Config built successfully"
