{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./style.nix
  ];

  config = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
      overwriteBackup = true;
      users.vika4ka = {
        imports = with inputs.dotfiles.homeModules; [
          anyrun
          cli
          email
          ghostty
          hyprland
          media
          pipewire
          sioyek
          tmux
          xdg
          transient-services
          zen
          ./common.nix
          inputs.sops-nix.homeManagerModule
        ];
        home.packages = with pkgs; [
          #svg and png editing
          gimp

          # office
          libreoffice-still

          #durov <3
          telegram-desktop
          #ZUCK
          wasistlos

          #10xorganization
          obsidian
          pdfannots2json
          tesseract

          #game time
          vesktop
          # wine-discord-ipc-bridge

          #science
          zotero

          #study
          anki

          #file manager
          (
            thunar.override {
              thunarPlugins = [
                thunar-archive-plugin
                thunar-media-tags-plugin
              ];
            }
          )
        ];
        sops = {
          age.keyFile = "/home/vika4ka/.config/sops/age/keys.txt";
          defaultSopsFormat = "binary";
          secrets = {
            weather.sopsFile = ../../vars/shared/vika4ka/weather/secret;
          };
        };
        home.stateVersion = "25.05";
      };
    };

    clan.core.vars.generators.vika4ka = {
      share = true;
      files = {
        weather.deploy = false;
      };
      prompts = {
        weather = {
          description = "OpenWeathe API key";
          persist = true;
          type = "hidden";
        };
      };
    };

    networking.networkmanager.ensureProfiles.profiles = import ./nm.nix;
    security.pam.services.greetd.enableGnomeKeyring = true;

    environment.persistence."/persistent" = {
      users.vika4ka = {
        directories = [
          "Code"
          "Downloads"
          "Documents"
          "Pictures"
          "Videos"
          "Music"
          "Zotero"
          ".thunderbird"
          ".pki"
          ".steam"
          ".yubico"
          ".zcn"
          ".zen"
          ".zotero"
          ".local"
          ".config"
          ".cache"
        ];
        files = [
          ".ssh/known_hosts"
        ];
      };
    };
  };
}
