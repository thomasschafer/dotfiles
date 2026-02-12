{
  username = "tomschafer";
  hostname = "nix-server";
  system = "x86_64-linux";
  isServer = true;
  enableOpenClaw = true;
  enableTailscale = true;
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5Hpkryvlq80EYHlf5VAv1zD7t3d8usl02rOCBYi1ti nix-server"
  ];
}
