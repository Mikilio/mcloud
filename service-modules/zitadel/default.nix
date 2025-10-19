{
  clanLib,
  exports,
  lib,
  directory,
  ...
}: let
  pickBestHost = hosts: let
    extractHost = host:
      if host ? var
      then
        clanLib.getPublicValue (
          host.var
          // {
            flake = directory;
          }
        )
      else host.plain;

    classifyHost = host: let
      cleaned = lib.removeSuffix "]" (lib.removePrefix "[" host);
    in
      if lib.hasInfix ":" cleaned
      then "ipv6"
      else if builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" cleaned != null
      then "ipv4"
      else "hostname";

    extractedHosts = map extractHost hosts;
    categorized = lib.groupBy classifyHost extractedHosts;
    hostnames = categorized.hostname or [];
    ipv6s = categorized.ipv6 or [];
    ipv4s = categorized.ipv4 or [];
    cleanHost = host: lib.removeSuffix "]" (lib.removePrefix "[" host);
  in
    if hostnames != []
    then {
      address = cleanHost (builtins.head hostnames);
      type = "hostname";
    }
    else if ipv6s != []
    then {
      address = cleanHost (builtins.head ipv6s);
      type = "ipv6";
    }
    else if ipv4s != []
    then {
      address = cleanHost (builtins.head ipv4s);
      type = "ipv4";
    }
    else throw "pickBestHost: No valid hosts in list";

  how2ConnectTo = machine: let
    allInstances = clanLib.selectExports (s: s.roleName == "") exports;
    networks = builtins.filter (x: x.value.networking != null) (lib.attrsToList allInstances);
    sortedNetworks = lib.sortOn (x: -x.value.networking.priority) networks;
    sortedScopes = map (x: clanLib.parseScope x.name) sortedNetworks;
    canConnect = scope:
      clanLib.selectExports (s:
        s
        == (scope
          // {
            roleName = "peer";
            machineName = machine;
          }))
      exports;
    findConnection = scopes: let
      maybeConnection = canConnect (builtins.head scopes);
    in
      if scopes == []
      then []
      else
        (
          if (maybeConnection != {})
          then
            [
              (builtins.head (builtins.attrValues maybeConnection))
            ]
            ++ findConnection (builtins.tail scopes)
          else findConnection (builtins.tail scopes)
        );
  in (findConnection sortedScopes);
in {
  _class = "clan.service";
  manifest.name = "zitadel";
  manifest.description = "A identity and access management platform";
  manifest.categories = [
    "Auth"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.server = {
    description = "Machine running the service";
    interface = {lib, ...}: {
      options = {
        domain = lib.mkOption {
          type = lib.types.str;
          example = "bitwarden.example.com";
          description = "The domain to use for Zitadel";
        };
        port = lib.mkOption {
          type = lib.types.int;
          default = 9092;
          description = "The port to use for Zitadel";
        };
      };
    };
    perInstance = {
      instanceName,
      roles,
      exports,
      settings,
      machine,
      ...
    }: {
      nixosModule = {
        config,
        pkgs,
        lib,
        ...
      }: let
        ownMailserver = roles ? mailserver;
        mailer = builtins.head (builtins.attrNames roles.mailserver.machines);
        mailerSetting = roles.mailserver.machines.${mailer}.settings;
        ways2ConnectToMailer = how2ConnectTo mailer;
        connection = pickBestHost ((builtins.head ways2ConnectToMailer).peer.hosts);
      in {
        assertions = lib.mkIf ownMailserver [
          {
            assertion = (builtins.tryEval connection).success;
            message = ''
              Can not reach the mailserver via the specified network.
            '';
          }
        ];

        #TODO: properly review this setting
        clan.core.postgresql = {
          enable = true;
          backupDatabases.${instanceName} = {
            database = instanceName;
            stopOnRestore = ["vaultwarden"];
          };
        };

        services.postgresql = {
          ensureDatabases = [instanceName];
          ensureUsers = [
            {
              name = instanceName;
              ensureDBOwnership = true;
            }
          ];
        };

        clan.core.vars.generators = {
          ${instanceName} = {
            files.masterKey.owner = config.services.zitadel.user;
            script = ''
              head -c 32 /dev/random > $out/masterKey
            '';
          };

          "${instanceName}-db" = {
            share = true;
            files.env.owner = config.services.zitadel.user;
            files.hash.secret = false;
            runtimeInputs = [pkgs.python3 pkgs.pwgen];
            script = ''
              password="$(pwgen 20 1 | tr -d '\n')"
              cat > "$out"/env <<EOF
              Database:
                postgres:
                  User:
                    Password: $password
              EOF

              echo -n "$password" | python3 ${./scram-sha-256.py} | tr -d "\n" > $out/hash
            '';
          };

          "${instanceName}-smtp" = {
            prompts = lib.mkIf (!ownMailserver) {
              password = {
                description = "SMTP password for Zitadel";
                persist = true;
              };
              user = {
                description = "SMTP username for Zitadel";
                persist = true;
              };
              sender = {
                description = "SMTP sender  for Zitadel";
                persist = true;
              };
              host = {
                description = "SMTP host for Zitadel";
                persist = true;
              };
            };
            files =
              if ownMailserver
              then {
                hash.secret = false;
                env.owner = config.services.zitadel.user;
              }
              else {
                user.secret = false;
                sender.secret = false;
                host.secret = false;
                env.owner = config.services.zitadel.user;
              };
            runtimeInputs = [pkgs.coreutils] ++ (lib.optionals ownMailserver [pkgs.mkpasswd pkgs.pwgen]);
            script =
              if ownMailserver
              then #bash
                ''
                  SMTP_PASSWORD="$(pwgen 20 1 | tr -d '\n')"

                  cat > "$out"/env <<EOF
                  DefaultInstance:
                    SMTPConfiguration:
                      SMTP:
                        Password: $SMTP_PASSWORD
                  EOF

                  echo "$SMTP_PASSWORD" | mkpasswd -sm bcrypt | tr -d "\n" > "$out"/hash
                ''
              else #bash
                ''
                  cat > "$out"/env <<EOF
                  SMTP_PASSWORD="$(cat "$prompts"/password)"
                  EOF
                '';
          };
        };

        #TODO: need general ex;port for used interfaces
        networking.firewall.interfaces.mycelium.allowedTCPPorts = [settings.port];
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [settings.port];

        services.zitadel = {
          enable = true;
          masterKeyFile = config.clan.core.vars.generators.${instanceName}.files.masterKey.path;
          tlsMode = "external";
          extraSettingsPaths = [
            config.clan.core.vars.generators."${instanceName}-smtp".files.env.path
            config.clan.core.vars.generators."${instanceName}-db".files.env.path
          ];
          steps = {
            FirstInstance = {
              Skip = true;
            };
          };
          settings = {
            Port = settings.port;

            ExternalDomain = settings.domain;
            ExternalPort = 443;
            ExternalSecure = true;

            Tracing.Type = "otel";
            Telemetry.Enabled = true;

            DefaultInstance = {
              LoginPolicy = {
                AllowRegister = false;
                ForceMFA = true;
              };
              LockoutPolicy = {
                MaxPasswordAttempts = 5;
                MaxOTPAttempts = 10;
              };
              SMTPConfiguration = lib.mkIf ownMailserver {
                SMTP = {
                  Host = connection.address;
                  User = mailerSetting.username;
                };
                From = mailerSetting.sender;
                FromName = "Zitadel";
              };
            };

            Database.postgres = {
              Host = "localhost";
              # Zitadel will report error if port is not set
              Port = 5432;
              Database = instanceName;
              User = {
                Username = instanceName;
                SSL.Mode = "disable";
              };
              Admin = {
                Username = instanceName;
                SSL.Mode = "disable";
                ExistingDatabase = instanceName;
              };
            };
          };
        };
      };
    };
  };

  #NOTE: Optional Roles
  roles.mailserver = {
    description = "A machine running a NixOS Mailserver";
    interface = {lib, ...}: {
      options = {
        network = lib.mkOption {
          type = lib.types.str;
          description = "Name of the Instance providing the Network connection to the server";
          example = "mycelium";
        };
        username = lib.mkOption {
          type = lib.types.str;
          description = "User name to use for the service account";
          example = "zitadel";
        };
        sender = lib.mkOption {
          type = lib.types.str;
          description = "Full email address to user for the sender";
          example = "zitadel@example.com";
        };
        security = lib.mkOption {
          type = lib.types.enum ["starttls" "force_tls" "off"];
          default = "starttls";
          description = ''
            Chose the type of SMTP or submission connection you want to use.

            When using VPN or using a local server, choosing "off" is the preffered solution.
            ```.
          '';
        };
      };
    };

    perInstance = {
      instanceName,
      roles,
      settings,
      ...
    }: {
      nixosModule = {
        config,
        lib,
        ...
      }: let
        server = builtins.head (builtins.attrNames roles.server.machines);
      in {
        assertions = [
          {
            assertion = config ? mailserver && config.mailserver.enable;
            message = ''
              The chosen machine does not have a mailserver enabled.
            '';
          }
        ];

        networking.firewall = lib.mkMerge [
          (lib.mkIf (settings.security == "off") {
            interfaces.tailscale0.allowedUDPPorts = [25];
            interfaces.mycelium.allowedUDPPorts = [25];
          })
          (lib.mkIf (settings.security == "starttls") {
            interfaces.tailscale0.allowedUDPPorts = [587];
            interfaces.mycelium.allowedUDPPorts = [587];
          })
          (lib.mkIf (settings.security == "force_tls") {
            interfaces.tailscale0.allowedUDPPorts = [465];
            interfaces.mycelium.allowedUDPPorts = [465];
          })
        ];

        mailserver = {
          enableSubmission = lib.mkIf (settings.security == "starttls") true;
          enableSubmissionSsl = lib.mkIf (settings.security == "force_tls") true;
          loginAccounts.${settings.username} = {
            hashedPassword = clanLib.getPublicValue {
              flake = directory;
              file = "hash";
              generator = "${instanceName}-smtp";
              machine = server;
            };
            aliases = [settings.sender];
          };
        };
      };
    };
  };

  roles.proxy = {
    description = ''
      A public machine that may or may not be connected to the tailnet. It will run an nginx proxy to make the headscale server reachable.
      If no machine is specified headscale will run without proxy.
    '';
    perInstance = {
      roles,
      exports,
      ...
    }: {
      nixosModule = {lib, ...}: {
        services.nginx = let
          server = builtins.head (builtins.attrNames roles.server.machines);
          serverSettings = roles.server.machines.${server}.settings;
          ways2ConnectToServer = how2ConnectTo server;
        in {
          enable = true;
          recommendedProxySettings = true;

          upstreams."zitadel-backend" = {
            servers = builtins.listToAttrs (
              lib.imap0 (
                i: x: let
                  host = pickBestHost x.peer.hosts;
                  address =
                    if host.type == "ipv6"
                    then "[${host.address}]"
                    else host.address;
                in
                  lib.nameValuePair
                  "${address}:${builtins.toString serverSettings.port}"
                  {
                    max_fails = 3;
                    fail_timeout = "30s";
                    backup = i > 0;
                  }
              )
              ways2ConnectToServer
            );
          };

          virtualHosts."${serverSettings.domain}" = {
            forceSSL = true;
            locations."/" = {
              extraConfig = ''
                grpc_pass grpc://zitadel-backend:${builtins.toString serverSettings.port};
                grpc_set_header Host $host;
                grpc_set_header X-Forwarded-Proto https;
              '';
            };
          };
        };
      };
    };
  };
}
