#!/bin/bash

# Find and execute setup scripts in subdirectories
find $(pwd) -mindepth 2 -type f -name 'setup.sh' -execdir bash {} \;

echo "Setup complete"
