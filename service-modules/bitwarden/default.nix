{
  lib,
  clanLib,
  exports,
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

  manifest = {
    name = "bitwarden";
    description = "A federated password manager for individuals and organizations";
    categories = ["Service" "Security"];
    readme = builtins.readFile ./README.md;
    exports.out = ["endpoints"];
  };

  roles.client = {
    description = "A client machine owned by a user pre-configured to use the Vault";

    perInstance = {...}: {
      nixosModule = {pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          bitwarden-desktop
          rbw
        ];
      };
    };
  };

  roles.server = {
    description = "The machine running the Vault";

    interface = {lib, ...}: {
      options = {
        domain = lib.mkOption {
          type = lib.types.str;
          example = "bitwarden.example.com";
          description = "The domain to use for Vaultwarden";
        };

        port = lib.mkOption {
          type = lib.types.int;
          default = 3011;
          description = "The port to use for Vaultwarden";
        };

        dataDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Main data folder
            This can be a path to local folder or a path to an external location
            depending on features enabled at build time. Possible external locations:

            - AWS S3 Bucket (via `s3` feature): s3://bucket-name/path/to/folder

            When a value is set here then TMP_FOLDER and  TEMPLATES_FOLDER are placed in /run/vaultwarden.
          '';
        };

        enableWebUI = lib.mkEnableOption "Enables the WebUI";

        enableHaveIBeenPwned = lib.mkEnableOption ''
          Enable HaveIBeenPwned integration.
          Will also add a generator prompting for API key.
        '';

        yubicoIntegration = {
          enable = lib.mkEnableOption ''
            Enable yubico integration for MFA/2FA.

            Will also add a generator prompting for identity, key and host.
            Create an account and protect an application as mentioned in this link to acquire the values (only the first step, not the rest):
            https://help.bitwarden.com/article/setup-two-step-login-duo/#create-a-duo-security-account
          '';
          server = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Optional custom OTP server.
            '';
          };
        };

        globalDuoIntegration = {
          enable = lib.mkEnableOption ''
            Enable duo integration for MFA/2FA globally.

            Will also add a generator for identity and key that can be aqcuired by following instructions on
            on https://upgrade.yubico.com/getapikey/
          '';
          server = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              API Hostname
            '';
          };
        };

        pushNotifications = {
          enable = lib.mkEnableOption ''
            Enable push notifications.
            Will also add a generator for identity and key that can be aqcuired on https://bitwarden.com/host
          '';
          region = lib.mkOption {
            type = lib.types.enum ["eu" "us"];
            default = false;
            description = ''
              Region of server used for push relay.
            '';
          };
        };

        signupMode = lib.mkOption {
          type = lib.types.enum ["allow" "lock" "email"];
          default = "allow";
          description = "Allow signups for new users";
        };

        smtp = {
          mailserver = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Address of the mailserver. If `smtp.network` is set then this parameter will be interpreted as a machine name.";
            example = "mail-server";
          };
          network = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Name of the Instance providing the Network connection to the mailserver";
            example = "mycelium";
            default = null;
          };
          username = lib.mkOption {
            type = lib.types.str;
            description = "User name to use for the service account";
            example = "vault";
            default = "vaultwarden";
          };
          sender = lib.mkOption {
            type = lib.types.str;
            description = "Full email address to use for the sender";
            example = "vaultwarden@example.com";
          };
          security = lib.mkOption {
            type = lib.types.enum ["starttls" "force_tls" "off"];
            default = "starttls";
            example = "off";
            description = ''
              Chose the type of SMTP or submission connection you want to use.

              When using VPN or using a local server, choosing "off" is the preferred solution.
            '';
          };
        };
      };
    };

    perInstance = {
      settings,
      instanceName,
      exports,
      mkExports,
      ...
    }: {
      exports = mkExports {
        endpoints.hosts = [ settings.domain ];
      };
      nixosModule = {
        config,
        pkgs,
        lib,
        ...
      }: let
        # Helper variables for readability
        ownMailserver = settings.smtp.mailserver != null;
        useSendmail = ownMailserver && settings.smtp.security == "off";

        connection =
          pickBestHost
          (builtins.head (builtins.attrValues (clanLib.selectExports (
              s:
                s.instanceName
                == settings.smtp.network
                && s.machineName == settings.smtp.mailserver
            )
            exports))).peer.hosts;
      in {
        assertions = [
          {
            assertion = (builtins.tryEval connection).success;
            message = ''
              Can not reach the mailserver via the specified network b.
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

        services.nginx = {
          enable = true;
          virtualHosts = {
            "${settings.domain}" = {
              forceSSL = true;
              extraConfig = ''
                client_max_body_size 128M;
              '';
              locations."/" = {
                proxyPass = "http://localhost:${builtins.toString settings.port}";
                proxyWebsockets = true;
              };
              locations."/notifications/hub" = {
                proxyPass = "http://localhost:${builtins.toString settings.port}";
                proxyWebsockets = true;
              };
              locations."/notifications/hub/negotiate" = {
                proxyPass = "http://localhost:${builtins.toString settings.port}";
                proxyWebsockets = true;
              };
            };
          };
        };

        clan.core.vars.generators = {
          vaultwarden-admin = {
            files.password = {};
            files.env = {};
            runtimeInputs = with pkgs; [
              coreutils
              pwgen
              libargon2
              openssl
            ];
            script = ''
              ADMIN_PWD=$(pwgen 16 -n1 | tr -d "\n")
              ADMIN_HASH=$(echo -n "$ADMIN_PWD" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4)

              config="
              ADMIN_TOKEN=\"$ADMIN_HASH\"
              "
              echo -n "$ADMIN_PWD" > "$out"/password
              echo -n "$config" > "$out"/env
            '';
          };

          vaultwarden-smtp = {
            prompts = lib.mkIf (!ownMailserver) {
              password = {
                description = "SMTP password for Vaultwarden";
                persist = true;
              };
            };
            files =
              if ownMailserver
              then {
                hash.secret = false;
                env = {};
              }
              else {
                env = {};
              };
            runtimeInputs = [pkgs.coreutils] ++ (lib.optionals ownMailserver [pkgs.mkpasswd pkgs.pwgen]);
            script = ''
              ${lib.optionalString ownMailserver ''
                SMTP_PASSWORD="$(pwgen 20 1 | tr -d '\n')"
              ''}

              cat > "$out"/env <<EOF
              SMTP_PASSWORD="${lib.optionalString (!ownMailserver) "$(cat \"$prompts\"/password)"}${lib.optionalString ownMailserver "$SMTP_PASSWORD"}"
              EOF

              ${lib.optionalString ownMailserver ''
                echo "$SMTP_PASSWORD" | mkpasswd -sm bcrypt | tr -d "\n" > "$out"/hash
              ''}
            '';
          };

          vaultwarden-hibp = lib.mkIf settings.enableHaveIBeenPwned {
            prompts.api-key.description = "API key for HaveIBeenPwned in Vaultwarden";
            files.env = {};
            runtimeInputs = with pkgs; [coreutils];
            script = ''
              cat > "$out"/env <<EOF
              HIBP_API_KEY="$(cat "$prompts"/api-key)"
              EOF
            '';
          };

          vaultwarden-yubico = lib.mkIf settings.yubicoIntegration.enable {
            prompts.client-id.description = "Client ID for yubico integration in Vaultwarden";
            prompts.client-secret.description = "Client secret for yubico integration in Vaultwarden";
            files.env = {};
            runtimeInputs = with pkgs; [coreutils];
            script = ''
              cat > "$out"/env <<EOF
              YUBICO_CLIENT_ID=$(cat "$prompts"/client-id)
              YUBICO_SECRET_KEY=$(cat "$prompts"/client-secret)
              EOF
            '';
          };

          vaultwarden-duo = lib.mkIf settings.globalDuoIntegration.enable {
            prompts.client-id.description = "Client ID for duo integration in Vaultwarden";
            prompts.client-secret.description = "Client secret for duo integration in Vaultwarden";
            files.env = {};
            runtimeInputs = with pkgs; [coreutils];
            script = ''
              cat > "$out"/env <<EOF
              PUSH_ENABLED=true
              DUO_IKEY=$(cat "$prompts"/client-id)
              DUO_SKEY=$(cat "$prompts"/client-secret)
              EOF
            '';
          };

          vaultwarden-bw = lib.mkIf settings.pushNotifications.enable {
            prompts.client-id.description = "Installation ID for push-notifications in Vaultwarden";
            prompts.client-secret.description = "Installation Key for push-notifications in Vaultwarden";
            files.env = {};
            runtimeInputs = with pkgs; [coreutils];
            script = ''
              cat > "$out"/env <<EOF
              PUSH_ENABLED=true
              PUSH_INSTALLATION_ID=$(cat "$prompts"/client-id)
              PUSH_INSTALLATION_KEY=$(cat "$prompts"/client-secret)
              EOF
            '';
          };
        };

        # Systemd service configuration - grouped by condition
        systemd.services.vaultwarden.serviceConfig = lib.mkMerge [
          {
            EnvironmentFile = map (attr: attr.value.files.env.path) (
              builtins.filter (attr: lib.hasPrefix "vaultwarden" attr.name) (
                lib.attrsToList config.clan.core.vars.generators
              )
            );
          }
          (lib.mkIf useSendmail {
            RestrictAddressFamilies = ["AF_NETLINK"];
            ReadWritePaths = [config.services.postfix.settings.main.queue_directory];
          })
        ];

        services.vaultwarden = {
          enable = true;
          dbBackend = "postgresql";
          config = lib.mkMerge [
            # Core configuration
            {
              DOMAIN = "https://${settings.domain}";
              SIGNUPS_ALLOWED = settings.signupMode != "locked";
              SIGNUPS_VERIFY = settings.signupMode == "email";
              ROCKET_PORT = builtins.toString settings.port;
              DATABASE_URL = "postgresql://"; # TODO: This should be set upstream if dbBackend is set to postgresql
              ENABLE_WEBSOCKET = true;
              ROCKET_ADDRESS = "127.0.0.1";
              SMTP_FROM = settings.smtp.sender;
              SMTP_SECURITY = settings.smtp.security;
              SMTP_DEBUG = true;
            }

            (lib.mkIf (settings.dataDir != null) {
              DATA_FOLDER = settings.dataDir;
              TMP_FOLDER = "/run/vaultwarden/tmp";
              TEMPLATES_FOLDER = "/run/vaultwarden/templates";
            })

            # Push notifications - US region
            (with settings.pushNotifications; (lib.mkIf (enable && region == "us") {
              PUSH_RELAY_URI = "https://push.bitwarden.com";
              PUSH_IDENTITY_URI = "https://identity.bitwarden.com";
            }))

            # Push notifications - EU region
            (with settings.pushNotifications; (lib.mkIf (enable && region == "eu") {
              PUSH_RELAY_URI = "https://api.bitwarden.eu";
              PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
            }))

            # SMTP - external mailserver
            (lib.mkIf (!ownMailserver) {
              SMTP_HOST = settings.smtp.mailserver;
            })

            # SMTP - own mailserver
            (lib.mkIf ownMailserver {
              SMTP_HOST = "[${connection.address}]";
            })

            # Use sendmail for local delivery
            (lib.mkIf useSendmail {
              USE_SENDMAIL = true;
              SENDMAIL_COMMAND = lib.getExe' pkgs.postfix "sendmail";
            })

            # Use authenticated SMTP
            (lib.mkIf (settings.smtp.security != "off") {
              SMTP_USERNAME = settings.smtp.username;
            })
          ];
        };

        # Postfix relay configuration
        services.postfix = lib.mkIf useSendmail {
          enable = true;
          setSendmail = false;
          settings.main.relayhost = ["[${connection.address}]:25"];
        };

        users.users.vaultwarden.extraGroups = lib.mkIf useSendmail ["postdrop"];
      };
    };
  };

  roles.mailserver = {
    description = "A machine running a NixOS Mailserver";

    perInstance = {
      roles,
      exports,
      ...
    }: {
      nixosModule = {
        config,
        pkgs,
        lib,
        ...
      }: let
        server = builtins.head (builtins.attrNames roles.server.machines);
        smtpSettings = roles.server.machines.${server}.settings.smtp;

        connection =
          pickBestHost
          (builtins.head (builtins.attrValues (clanLib.selectExports (
              s:
                s.instanceName
                == smtpSettings.network
                && s.machineName == server
            )
            exports))).peer.hosts;
      in {
        assertions = [
          {
            assertion = config ? mailserver && config.mailserver.enable;
            message = ''
              The chosen machine does not have a mailserver enabled.
            '';
          }
        ];

        # Firewall rules - grouped by security setting
        networking.firewall = lib.mkMerge [
          (lib.mkIf (smtpSettings.security == "off") {
            interfaces.tailscale0.allowedTCPPorts = [25];
            interfaces.mycelium.allowedTCPPorts = [25];
          })
          (lib.mkIf (smtpSettings.security == "starttls") {
            interfaces.tailscale0.allowedTCPPorts = [587];
            interfaces.mycelium.allowedTCPPorts = [587];
          })
          (lib.mkIf (smtpSettings.security == "force_tls") {
            interfaces.tailscale0.allowedTCPPorts = [465];
            interfaces.mycelium.allowedTCPPorts = [465];
          })
        ];

        mailserver = {
          enableSubmission = lib.mkIf (smtpSettings.security == "starttls") true;
          enableSubmissionSsl = lib.mkIf (smtpSettings.security == "force_tls") true;
          loginAccounts."${smtpSettings.username}@mikilio.com" = {
            hashedPassword = clanLib.getPublicValue {
              file = "hash";
              generator = "vaultwarden-smtp";
              machine = server;
              flake = directory;
            };
            aliases = [smtpSettings.sender];
          };
        };

        # Postfix and rspamd configuration for unauthenticated relay
        services = lib.mkIf (smtpSettings.security == "off") {
          postfix = {
            mapFiles = {
              service_clients = pkgs.writeText "service_clients" ''
                [${connection.address}]    allow_vaultwarden_only
              '';

              vaultwarden_senders = pkgs.writeText "vaultwarden_senders" ''
                ${smtpSettings.sender}    OK
              '';
            };

            settings.main = {
              smtpd_restriction_classes = ["allow_vaultwarden_only"];

              allow_vaultwarden_only = [
                "check_sender_access hash:/etc/postfix/vaultwarden_senders"
                "reject"
              ];

              smtpd_relay_restrictions = lib.mkBefore [
                "check_client_access hash:/etc/postfix/service_clients"
              ];
            };
          };

          rspamd.locals."settings.conf".text = ''
            mycelium_relay {
              priority = high;
              ip = "${connection.address}";
              want_spam = yes;
            }
          '';
        };
      };
    };
  };

  perMachine = {instances, ...}: {
    nixosModule = {lib, ...}: {
      assertions =
        lib.concatLists
        (lib.mapAttrsToList (
            instanceName: instanceInfo:
              with builtins; let
                getNof = role:
                  if (instanceInfo.roles ? ${role})
                  then length (attrNames instanceInfo.roles.${role}.machines)
                  else 0;
                nofVaults = getNof "server";
                nofMailserver = getNof "mailserver";
              in [
                {
                  assertion = nofVaults > 0;
                  message = ''
                    Instance ${instanceName} of service bitwarden needs to specify at least one server.
                  '';
                }
                {
                  assertion = nofMailserver <= 1;
                  message = ''
                    Instance ${instanceName} of service bitwarden can specify at most one mailserver.
                  '';
                }
              ]
          )
          instances);
    };
  };
}
