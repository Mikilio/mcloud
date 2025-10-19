{
  inputs = {
    clan-core = {
      url = "https://git.clan.lol/Mikilio/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs"; # Avoid this if using nixpkgs stable.
      inputs.flake-parts.follows = "flake-parts"; # New
    };
    nixpkgs.follows = "dotfiles/nixpkgs";
    nixpkgs-stable.follows = "dotfiles/nixpkgs-stable";
    sops-nix.follows = "dotfiles/sops-nix";
    stylix.follows = "dotfiles/stylix";
    home-manager.follows = "dotfiles/home-manager";
    dotfiles.url = "github:Mikilio/dotfiles";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    impermanence.url = "github:nix-community/impermanence";
    srvos.url = "github:nix-community/srvos";
    nur.url = "github:nix-community/NUR";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    mailserver.url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
  };
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} (
      {flake-parts-lib, ...}: {
        systems = [
          "x86_64-linux"
        ];

        perSystem = {
          inputs',
          pkgs,
          ...
        }: {
          devShells.default = pkgs.mkShell {
            packages = [
              inputs'.clan-core.packages.clan-cli
              pkgs.opentofu
            ];
          };
        };

        imports = with inputs; [
          clan-core.flakeModules.default
        ];

        clan = {
          meta.name = "mcloud";
          meta.domain = "mcloud";

          specialArgs = {inherit inputs;};

          secrets.age.plugins = [
            "age-plugin-yubikey"
          ];

          modules = {
            tailscale = ./service-modules/tailscale;
            bitwarden = ./service-modules/bitwarden;
            zitadel = ./service-modules/zitadel;
            wordpress = ./service-modules/wordpress;
          };

          inventory = {
            tags = {
              config,
              machines,
              lib,
              ...
            }:
              with builtins; {
                public = ["gate"];
                "owner:mikilio" = ["elitebook"];
                "owner:vika4ka" = ["acer"];
                notPublic = filter (name: !(elem name config.public)) config.all;
                userOwned = concatLists (lib.mapAttrsToList (name: value:
                  if lib.hasPrefix "owner" name
                  then value
                  else [])
                config);
                clanOwned = filter (name: !(elem name config.userOwned)) config.all;
              };

            machines = {
              gate = {
                # deploy.buildHost = "mikilio@elitebook";
              };
              brain = {
                # deploy.buildHost = "mikilio@elitebook";
              };
              wp1 = {
                # deploy.buildHost = "mikilio@elitebook";
              };
              elitebook = {
                deploy.targetHost = "root@elitebook";
              };
              acer = {
                # deploy.buildHost = "mikilio@elitebook";
              };
            };
            instances = {
              sshd = {
                roles.server = {
                  tags.all = {};
                  settings = {
                    authorizedKeys = {
                      "mikilio" = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDYPjdpzOZCLJfSGaeMo7yYBmTTVSnjf04aB3K74qZN9zOBotyBmLqD+SzVBrvbmGH3byRZF1V5bWdckc9ttdeJnLGJBtBNpBoCEb7V9AufzUC6njka2pvw8yIrOJZmK7JHK/IY21Wjsagu10f4OdUWF+CRevLmECOK0CJQmzbpjksFqVB9vaCI6fTBm0ZD+/AezXideg4FDBnfzjvT/0WEJbYj9yV6UO7rNIx7mYIErCnTg3PUUMuNz1By3pUGBjXnhDogW9KgrDqGDYbkqalxiNOW35D0QyxiIBhqy96B1Irt+dIQPG2qj6uAsMqfAyycGyZ34QukxKbudE/j+F/JlmGAfB3wbS1zaIyASd3vV0nO8zp2fQcyyP2wkjYe/qB9QFnNDh6/OUANKtMdXwFL94ZYJd4ZVwxsVZPdFlCS34Jf10o4P0rXAEcsQplsHFo0bjxn5yySwjEl26HZKBKd7PYQ7hb/zMCVroqcmBLoqGLD5vDaeZ3EMvTIHw6Gumbg6TggLopCzdwNiUqYdqelXwVC/mdpdyOYP/aBzMuN7FzOkehC4p99Pn3tiS+saqmU6em5y4l+U722J9fuKppYIB1VvZY8sDLQlxXepUykNzj0wwJse9fcgZ8X2P48F4gg8OvjZJ/Efyygvi6xsFoSmsP5itC0PIUG95aLhE78vQ== cardno:23_674_753";
                    };
                    hostKeys.rsa.enable = true;
                  };
                };
                roles.client.tags.all = {};
              };

              vika4ka = {
                module.name = "users";

                roles.default.tags = ["owner:vika4ka"];

                roles.default.settings = {
                  user = "vika4ka"; #

                  groups = [
                    "adbusers"
                    "input"
                    "tss" #for swtpm
                    "jlink"
                    "networkmanager"
                    "plugdev"
                    "keys"
                    "transmission"
                    "video"
                    "i2c"
                    "wheel"
                    "podman"
                    "ydotool"
                    "disk"
                    "davfs2"
                  ];
                  share = true;
                };
                roles.default.extraModules = [
                  ./users/vika4ka/laptop.nix
                ];
              };

              mikilio-laptop = {
                #

                module.name = "users";

                roles.default.tags = ["owner:mikilio"];

                roles.default.settings = {
                  user = "mikilio"; #

                  groups = [
                    "adbusers"
                    "input"
                    "tss" #for swtpm
                    "jlink"
                    "networkmanager"
                    "plugdev"
                    "keys"
                    "transmission"
                    "video"
                    "i2c"
                    "wheel"
                    "podman"
                    "ydotool"
                    "davfs2"
                    "disk"
                  ];
                  share = true;
                };
                roles.default.extraModules = [
                  ./users/mikilio/laptop.nix
                ];
              };

              # yggdrasil = {
              #   roles.default.tags.all = {};
              # };

              internet = {
                roles.default = {
                  machines = {
                    gate.settings.host = "mail.mikilio.com";
                  };
                };
              };

              mycelium = {
                roles.peer = {
                  tags.all = {};
                  extraModules = [
                    {
                      networking.firewall.interfaces.mycelium.allowedTCPPorts = [22];
                    }
                  ];
                };
              };

              # tor = {
              #   roles.server.tags.nixos = {};
              # };
              #
              pki = {
                module.name = "pki";
                roles.default.tags.all = {};
              };

              tailscale = {
                module.name = "tailscale";
                module.input = "self";
                roles = {
                  client.tags = ["userOwned"];
                  server.tags = ["clanOwned"];
                  proxy.machines.gate = {};
                  controller.machines.brain.settings = let
                    adminUser = "mikilio@";
                  in {
                    domain = "ts.mikilio.com";
                    port = 3009;
                    interface = "mycelium";
                    globalNameservers = ["https://dns.nextdns.io/193dfc"];
                    aclConfig = {
                      # Groups definition
                      groups = {
                        "group:admins" = ["${adminUser}"];
                      };

                      # Tag definition
                      tagOwners = {
                        "tag:server" = ["${adminUser}"];
                      };

                      acls = [
                        # Allow admin to connect to their own services
                        {
                          action = "accept";
                          src = ["group:admins"];
                          dst = ["*:*"];
                        }
                        {
                          action = "accept";
                          src = ["autogroup:member"];
                          dst = ["tag:server:80,443"];
                        }
                      ];

                      ssh = [
                        {
                          action = "accept";
                          src = ["autogroup:member"];
                          dst = ["autogroup:self"];
                          users = ["autogroup:nonroot" "root"];
                        }
                        {
                          action = "accept";
                          src = ["group:admins"];
                          dst = ["tag:server"];
                          users = ["autogroup:nonroot" "root"];
                        }
                      ];

                      # Auto-approvers section for routes
                      autoApprovers = {
                        routes = {
                          "0.0.0.0/0" = ["${adminUser}"];
                          "10.0.0.0/8" = ["${adminUser}"];
                          "192.168.0.0/16" = ["${adminUser}"];
                        };

                        exitNode = ["${adminUser}"];
                      };
                    };
                  };
                };
              };
              bitwarden = {
                module.name = "bitwarden";
                module.input = "self";
                roles = {
                  client.tags = ["userOwned"];
                  server.machines.brain.settings = {
                    domain = "vault.mcloud";
                    pushNotifications = {
                      enable = true;
                      region = "eu";
                    };
                    smtp = {
                      mailserver = "gate";
                      network = "mycelium";
                      sender = "no-reply@mikilio.com";
                      security = "off";
                    };
                  };
                  mailserver.machines.gate.settings = {};
                };
              };
              zitadel = {
                module.name = "zitadel";
                module.input = "self";
                roles = {
                  server.machines.brain.settings = {
                    domain = "auth.mikilio.com";
                  };
                  mailserver.machines.gate.settings = {
                    network = "mycelium";
                    username = "zitadel";
                    sender = "zitadel@mikilio.com";
                    security = "off";
                  };
                };
              };
              wp-site = {
                module.name = "wordpress";
                module.input = "self";
                roles = {
                  server.machines.wp1.settings = {
                    domain = "wp.mikilio.com";
                    port = 8081;
                  };
                  proxy.machines.gate = {};
                };
              };
            };
          };
        };
      }
    );
}
