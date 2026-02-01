{
  self,
  pkgs,
  hostConfig,
  ...
}:
{
  imports = [
    /etc/nixos/hardware-configuration.nix
  ];

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        hostConfig.username
      ];
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.05";

  nixpkgs.config.allowUnfree = true;

  networking = {
    hostName = hostConfig.hostname;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.${hostConfig.username} = {
    isNormalUser = true;
    home = "/home/${hostConfig.username}";
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = hostConfig.sshKeys;
  };

  security.sudo.wheelNeedsPassword = true;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
  ];

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
}
