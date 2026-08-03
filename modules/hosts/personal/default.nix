{
  username = "tomschafer";
  enableVSCode = false;
  # Prunes outdated versions and caches only. Formulae dropped from the Brewfile are
  # not auto-uninstalled; run `brew bundle cleanup --force` by hand for that.
  homebrew.pruneOldVersions = true;
  autohideDock = true;
}
