{
  config,
  lib,
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
      users.mikilio = {
        imports = with inputs.dotfiles.homeModules; [
          anyrun
          cli
          email
          gpg
          git
          ghostty
          hyprland
          media
          nushell
          # nvim
          neovix
          pass
          pipewire
          productivity
          # rofi
          sioyek
          spicetify
          ssh
          starship
          tmux
          transient-services
          xdg
          yazi
          zen
          ./common.nix
          inputs.sops-nix.homeManagerModule
        ];
        home.stateVersion = "25.05";
        sops = {
          defaultSopsFormat = "binary";
          secrets = {
            google-git.sopsFile = ../../vars/shared/mikilio/google-git/secret;
            weather.sopsFile = ../../vars/shared/mikilio/weather/secret;
            github.sopsFile = ../../vars/shared/mikilio/github/secret;
          };
        };
      };
    };

    services.teamviewer.enable = true;

    clan.core.vars.generators.mikilio = {
      share = true;
      files = {
        u2f = {
          restartUnits = ["chown-mikilio-u2f.service"];
          owner = "mikilio";
        };
        google-git.deploy = false;
        weather.deploy = false;
        github.deploy = false;
      };
      prompts = {
        u2f = {
          description = "U2F mapping of Mikilio's Yubikey";
          persist = true;
        };
        google-git = {
          description = "GMail app password for git emails";
          persist = true;
        };
        weather = {
          description = "OpenWeathe API key";
          persist = true;
        };
        github = {
          description = "GitHub API key";
          persist = true;
        };
      };
    };

    sops.secrets."vars/mikilio/u2f".path = "/home/mikilio/.config/Yubico/u2f_keys";

    programs.nh = {
      enable = true;
      flake = "/home/mikilio/Code/Public/github.com/Mikilio/dotfiles";
    };

    networking.networkmanager.ensureProfiles.profiles = import ./nm.nix;

    environment.persistence = {
      "/persistent/storage" = {
        users.mikilio = {
          directories = [
            "Desktop"
            "Code"
            "Documents"
            "Pictures"
            "Videos"
            "Music"
            "Zotero"
            ".thunderbird/default"
            ".pki"
            ".steam"
            ".yubico"
            ".zcn"
            ".zen"
            ".zotero"
            ".local/state"
            ".local/share/applications"
            ".local/share/atuin"
            ".local/share/calibre-ebook.com"
            ".local/share/com.yubico.yubioath"
            ".local/share/devenv"
            ".local/share/direnv"
            ".local/share/gnupg"
            ".local/share/keyrings"
            ".local/share/nvim"
            ".local/share/password-store"
            ".local/share/rbw"
            ".local/share/sioyek"
            ".local/share/TelegramDesktop"
            ".local/share/tmux"
            ".local/share/Trash"
            ".local/share/wasistlos"
            ".local/share/zoxide"

            #exceptions
            ".config/autostart"
            ".config/beets"
            ".config/Bitwarden"
            ".config/libreoffice"
            ".config/rclone"
            ".config/obs-studio"
            ".config/zen"
          ];
        };
      };
      "/persistent/cache" = {
        users.mikilio = {
          directories = [
            "Downloads"
            ".local/share/Steam"
            ".local/share/containers"

            #automated data
            ".local/share/nix"
            ".local/share/essentia"
            ".local/share/mpd"

            #Electron mess
            ".config/Morgen"
            ".config/obsidian"
            ".config/Element"
            ".config/teams-for-linux"
            ".config/wasistlos"
            ".config/vesktop"

            #actual caches
            ".cache/nix-index"
            ".cache/spotify"
            ".cache/vfs"
            ".cache/vfsMeta"
            ".cache/wasistlos"
          ];
          files = [
            ".ssh/known_hosts"
          ];
        };
      };
    };
  };
}
