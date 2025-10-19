{
  inputs,
  pkgs,
  ...
}: {
  imports = with inputs; [
    dotfiles.nixosModules.lanzaboote
    dotfiles.nixosModules.pipewire
    dotfiles.nixosModules.plymouth
    dotfiles.nixosModules.desktop-essentials
    dotfiles.nixosModules.graphics
    dotfiles.nixosModules.greetd
    dotfiles.nixosModules.power
    dotfiles.nixosModules.bluetooth
    dotfiles.nixosModules.hyprland
    dotfiles.nixosModules.gaming
    dotfiles.nixosModules.networking
    dotfiles.nixosModules.security
    dotfiles.nixosModules.home-manager
    dotfiles.nixosModules.nix
    dotfiles.nixosModules.tailscale
    dotfiles.nixosModules.overlays
    dotfiles.nixosModules.impermanence
    nur.modules.nixos.default
  ];

  dotfiles.security.target = "desktop";
  dotfiles.networking.target = "desktop";

  networking.hostName = "acer";

  # I have rocm support apparently
  nixpkgs.config.rocmSupport = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  # for electron
  security.unprivilegedUsernsClone = true;

  #TODO: find out which modules I actually need
  security.lockKernelModules = false;

  i18n = {
    defaultLocale = "en_US.UTF-8";
    # saves space
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "uk_UA.UTF-8/UTF-8"
      "de_DE.UTF-8/UTF-8"
    ];
  };

  clan.core.deployment.requireExplicitUpdate = true;
  # users.users.root.hashedPassword = "!";

  time.timeZone = "Europe/Berlin";
}
