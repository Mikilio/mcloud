{
  lib,
  config,
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
  manifest.name = "wordpress";
  manifest.description = "TODO";
  manifest.categories = [
    "Web"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.client = {
    description = "A client machine owned by a user pre-configured to use the Vault";

    perInstance = {...}: {
      nixosModule = {config, ...}: {};
    };
  };

  roles.server = {
    description = "The machine running the site";
    interface = {lib, ...}: {
      options = {
        domain = lib.mkOption {
          type = lib.types.str;
          example = "bitwarden.example.com";
          description = "The domain to use for site";
        };
        port = lib.mkOption {
          type = lib.types.int;
          default = 80;
          description = "The port to use for site";
        };
      };
    };

    perInstance = {
      settings,
      instanceName,
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
              Can not reach the mailserver via the specified network w.
            '';
          }
        ];

        clan.core.vars.generators = {
          wp-admin = {
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
          wp-smtp = {
            prompts = lib.mkIf (!ownMailserver) {
              password = {
                description = "SMTP password for Wordpress";
                persist = true;
              };
              user = {
                description = "SMTP username for Wordpress";
                persist = true;
              };
              sender = {
                description = "SMTP sender  for Wordpress";
                persist = true;
              };
              host = {
                description = "SMTP host for Wordpress";
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
                user.secret = false;
                sender.secret = false;
                host.secret = false;
                env = {};
              };
            runtimeInputs = [pkgs.coreutils] ++ (lib.optionals ownMailserver [pkgs.mkpasswd pkgs.pwgen]);
            script =
              if ownMailserver
              then #bash
                ''
                  SMTP_PASSWORD="$(pwgen 20 1 | tr -d '\n')"

                  cat > "$out"/env <<EOF
                  SMTP_PASSWORD="$SMTP_PASSWORD"
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

        #NOTE: need general export for intefaces in the future
        networking.firewall.interfaces.mycelium.allowedTCPPorts = [settings.port];
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [settings.port];

        services = {
          nginx = {
            virtualHosts."${settings.domain}" = {
              extraConfig = ''
                gzip on;
                gzip_vary on;
                gzip_comp_level 4;
                gzip_min_length 256;
                gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
                gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
              '';
              listen = [
                {
                  addr = "0.0.0.0";
                  port = settings.port;
                }
                {
                  addr = "[::]";
                  port = settings.port;
                }
              ];
            };
          };

          wordpress = {
            webserver = "nginx";
            sites.${settings.domain} = {
              languages = [pkgs.wordpressPackages.languages.de_DE];
              themes = {
                inherit
                  (pkgs.wordpressPackages.themes)
                  twentytwentythree
                  ;
              };
              plugins = {
                inherit
                  (pkgs.wordpressPackages.plugins)
                  antispam-bee
                  disable-xml-rpc
                  merge-minify-refresh
                  simple-login-captcha
                  wordpress-seo
                  webp-express
                  ;
              };
              settings = {
                WP_HOME = "https://${settings.domain}";
                WP_SITEURL = "https://${settings.domain}";
                FORCE_SSL_ADMIN = true;
                WP_DEBUG = true;
                WP_DEBUG_LOG = true;
              };
              extraConfig =
                #PHP
                ''
                  if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
                      $_SERVER['HTTPS'] = 'on';
                  }

                  if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
                      $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
                      $_SERVER['REMOTE_ADDR'] = trim($ips[0]);
                  }

                  ini_set( 'error_log', '/var/lib/wordpress/${settings.domain}/debug.log' );

                '';
              #
              #   add_action('phpmailer_init', function($phpmailer) {
              #       $phpmailer->isSMTP();
              #       $phpmailer->Host       = 'mail.mikilio.com';
              #       $phpmailer->Port       = 587;
              #       $phpmailer->SMTPSecure = 'tls';
              #       $phpmailer->SMTPAuth   = true;
              #       $phpmailer->Username   = 'wordpress@yourdomain.com';
              #       $phpmailer->Password   = '${config.age.secrets.wp-smtp-password.path}';  # or however you manage secrets
              #       $phpmailer->From       = 'noreply@yourdomain.com';
              #       $phpmailer->FromName   = 'Your Site';
              #   });
              #
              # '';
            };
          };
        };
        nixpkgs.overlays = [
          (self: super: {
            wordpress = super.wordpress.overrideAttrs (oldAttrs: rec {
              installPhase =
                oldAttrs.installPhase
                + ''
                  ln -s /var/lib/wordpress/${settings.domain}/mmr $out/share/wordpress/wp-content/mmr
                '';
            });
          })
        ];

        systemd.tmpfiles.rules = [
          "d '/var/lib/wordpress/${settings.domain}/mmr' 0750 wordpress wwwrun - -"
        ];
      };
    };
  };

  #NOTE: Optional Roles
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

          upstreams."wp-backend" = {
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
            enableACME = true;
            locations."/" = {
              proxyPass = "http://wp-backend";
              extraConfig = ''
              '';
            };
          };
        };
      };
    };
  };

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
          example = "wp";
        };
        sender = lib.mkOption {
          type = lib.types.str;
          description = "Full email address to user for the sender";
          example = "wp@example.com";
        };
        security = lib.mkOption {
          type = lib.types.enum ["starttls" "force_tls" "off"];
          default = "force_tls";
          description = ''
            Chose the type of SMTP or submission connection you want to use.

            When using VPN or using a local server, choosing "off" is the preffered solution.
            ```.
          '';
        };
      };
    };

    perInstance = {
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
              flake = ../..;
              file = "hash";
              generator = "wp-smtp";
              machine = server;
            };
            aliases = [settings.sender];
          };
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
                nofProxy = getNof "proxy";
                nofMailserver = getNof "mailserver";
              in [
                {
                  assertion = nofProxy <= 1;
                  message = ''
                    Instance ${instanceName} of service wordpress can specify at most one proxy.
                  '';
                }
                {
                  assertion = nofMailserver <= 1;
                  message = ''
                    Instance ${instanceName} of service wordpress can specify at most one mailserver.
                  '';
                }
              ]
          )
          instances);
    };
  };
}
