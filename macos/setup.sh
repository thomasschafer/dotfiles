#!/bin/bash

set -e
set -o pipefail

# Update dock icon size
defaults write com.apple.dock tilesize -int 50
# Minimise applications into icon in dock
defaults write com.apple.dock minimize-to-application -bool true
# Disable separate section for suggested and recent applications in dock
defaults write com.apple.dock show-recents -bool false

# Require password immediately after sleep or screen saver
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Update default location to save screenshots
mkdir -p $HOME/Documents/Screenshots
defaults write com.apple.screencapture location $HOME/Documents/Screenshots

# Ensure tap-hold repeats key
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

killall Dock
killall SystemUIServer
