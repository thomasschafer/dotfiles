# Update dock icon size
defaults write com.apple.dock tilesize -int 55
# Minimise applications into icon in dock
defaults write com.apple.dock minimize-to-application -bool true
# Disable separate section for suggested and recent applications in dock
defaults write com.apple.dock show-recents -bool false

# Update default location to save screenshots
mkdir -p ~/Documents/Screenshots
defaults write com.apple.screencapture location ~/Documents/Screenshots

killall Dock
killall SystemUIServer
