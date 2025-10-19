{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = with inputs; [
    nixos-hardware.nixosModules.hp-elitebook-845g9
    dotfiles.nixosModules.vm-dev
    dotfiles.nixosModules.thunderbolt
    dotfiles.nixosModules.lanzaboote
    dotfiles.nixosModules.pipewire
    dotfiles.nixosModules.plymouth
    dotfiles.nixosModules.desktop-essentials
    dotfiles.nixosModules.graphics
    dotfiles.nixosModules.greetd
    dotfiles.nixosModules.impermanence
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
    nur.modules.nixos.default
    ../../modules/duplicati.nix
    ../../modules/snapper.nix
  ];

  dotfiles.security.target = "desktop";
  dotfiles.networking.target = "desktop";

  networking.hostName = "elitebook";

  # compresses half the ram for use as swap
  zramSwap.enable = true;

  # I have rocm support apparently
  nixpkgs.config.rocmSupport = true;

  # virtualisation

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
    pcsclite
  ];

  boot = {
    binfmt.emulatedSystems = ["aarch64-linux"];
    kernelModules = [
      "f2fs"
    ];
    kernel.sysctl = {
      #better mmap entropy
      "vm.mmap_rnd_bits" = 32;
      "vm.mmap_rnd_compat_bits" = 16;
    };
    kernelParams = [
      "iommu=pt"
      "video=efifb:off"
      "fbcon=map:10"
      "pci=realloc"
      "acpi_enforce_resources=lax"
    ];
    # initrd.services.udev.rules =
    #   #udev
    #   ''
    #     SUBSYSTEM=="drm", KERNEL=="card0", ACTION=="add", RUN+="${pkgs.fbset}/bin/con2fbmap 1 1"
    #   '';
  };
  #to persist journal
  environment.etc."machine-id".text = "39bab0f0f3f34287810d06dc1877ba47";
  #TODO: find out which modules I actually need
  security.lockKernelModules = false;
  #stop generating annoying coredumps in home dir
  systemd.coredump.extraConfig = "Storage=journal";
  #for embedded systems
  hardware.libjaylink.enable = true;
  hardware.i2c.enable = true;

  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";

  documentation.dev.enable = true;

  i18n = {
    defaultLocale = "en_US.UTF-8";
    # saves space
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "ja_JP.UTF-8/UTF-8"
      "de_DE.UTF-8/UTF-8"
    ];
  };

  clan.core.deployment.requireExplicitUpdate = true;
  clan.core.state.persistence = {
    folders = ["/tmp/btrfs-bak"];

    preBackupScript = ''
      if [ -d "/tmp/btrfs-bak" ]; then
        btrfs subvolume delete "/tmp/btrfs-bak"
      fi

      btrfs subvolume snapshot -r "/persistent" "/tmp/btrfs-bak"
    '';

    postBackupScript = ''
      btrfs subvolume delete "/tmp/btrfs-bak"
    '';

    postRestoreScript = ''
      mkdir -p /persistent
      rsync --archive --delete --hard-links --sparse "/tmp/btrfs-bak/" "/persistent/"
    '';
  };

  security.pam.u2f.settings.authfile = config.clan.core.vars.generators.mikilio.files.u2f.path;

  time.timeZone = "Europe/Berlin";
  security.polkit.extraConfig =
    #lua
    ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" &&
          subject.isInGroup("disk")) {

          var program = action.lookup("program");
          var cmdline = action.lookup("command_line");
          var btrfsPath = "${pkgs.btrfs-progs}/bin/btrfs";

          if (program == btrfsPath) {
            var safeCommands = [
              " filesystem show",
              " filesystem df",
              " filesystem usage",
              " subvolume show",
              " subvolume list",
              " subvolume get-default",
              " device stats",
              " qgroup show",
              " quota rescan -s",
              " inspect-internal dump-tree",
              " inspect-internal dump-super",
              " inspect-internal inode-resolve",
              " inspect-internal logical-resolve",
              " inspect-internal subvolid-resolve",
              " inspect-internal rootid",
              " inspect-internal min-dev-size",
              " inspect-internal dump-csum",
              " inspect-internal map-swapfile",
              " property get",
              " property list",
              " scrub status",
              " balance status",
              " version"
            ];

            for (var i = 0; i < safeCommands.length; i++) {
              if (cmdline.indexOf(btrfsPath + safeCommands[i]) === 0) {
                return polkit.Result.YES;
              }
            }
          }
        }
      });
    '';
}
