# The `secret` command (see secret.sh), shared by everything in the dotfiles that keeps secrets in
# the keychain.
{ writeShellApplication }:

writeShellApplication {
  name = "secret";
  text = builtins.readFile ./secret.sh;
}
