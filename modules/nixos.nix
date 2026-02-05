{
  self,
  pkgs,
  lib,
  host,
  hostConfig,
  ...
}:
{
  imports = [
    ./hosts/${host}/hardware-configuration.nix
  ];

  assertions = [
    {
      assertion = hostConfig ? username;
      message = "hostConfig.username is required";
    }
    {
      assertion = hostConfig ? hostname;
      message = "hostConfig.hostname is required";
    }
    {
      assertion = hostConfig ? system;
      message = "hostConfig.system is required";
    }
    {
      assertion = hostConfig ? sshKeys && hostConfig.sshKeys != [ ];
      message = "hostConfig.sshKeys must be a non-empty list";
    }
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
      # Disable root login entirely - use sudo instead
      PermitRootLogin = "no";
      # Disable all password-based auth
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # Limit authentication attempts
      MaxAuthTries = 3;
      LoginGraceTime = 20;
      # Disconnect idle sessions
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      # Disable unnecessary features
      X11Forwarding = false;
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails = {
      sshd = {
        settings = {
          enabled = true;
          filter = "sshd[mode=aggressive]";
          maxretry = 3;
          bantime = "1h";
          findtime = "10m";
        };
      };
    };
  };

  users.users.root.openssh.authorizedKeys.keys = hostConfig.sshKeys;

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

  # Enable nix-ld to run dynamically linked binaries (e.g. Claude Code)
  programs.nix-ld.enable = true;

  # OpenClaw: enable lingering so user services start at boot
  system.activationScripts.openclawLingering = lib.mkIf (hostConfig.enableOpenClaw or false) ''
    ${pkgs.systemd}/bin/loginctl enable-linger ${hostConfig.username} || true
  '';
}
