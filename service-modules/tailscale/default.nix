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
  manifest.name = "tailscale";
  manifest.description = "Wireguard-based VPN mesh network with automatic IPv6 address allocation";
  manifest.categories = [
    "System"
    "Network"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.client = {
    description = "A machine owned by an actual user that want to reach services on the tailnet";

    perInstance = {...}: {
      nixosModule = {config, ...}: let
        cfg = config.services.tailscale;
      in {
        networking.firewall = {
          trustedInterfaces = [cfg.interfaceName];
          interfaces.${cfg.interfaceName}.allowedUDPPorts = [cfg.port];
        };

        services.tailscale = {
          enable = true;
          useRoutingFeatures = "client";
          openFirewall = false;
        };
      };
    };
  };

  roles.server = {
    description = "A machine owned by the clan that and may provide services";

    perInstance = {
      instanceName,
      roles,
      machine,
      ...
    }: {
      nixosModule = {
        config,
        pkgs,
        lib,
        ...
      }: let
        cfg = config.services.tailscale;
      in {
        networking.firewall = {
          trustedInterfaces = [cfg.interfaceName];
          interfaces.${cfg.interfaceName}.allowedUDPPorts = [cfg.port 22];
        };

        clan.core.vars.generators.${instanceName} = {
          files = {
            authkey.secret = true;
            "authkeys-dump.sql".secret = false;
          };
          share = false;
          runtimeInputs = with pkgs; [headscale sqlite];
          script = ''
            CONFIG_FILE="config.yaml"

            cat > "$CONFIG_FILE" <<EOF
            server_url: http://localhost:8080
            noise:
              private_key_path: noise_private.key
            database:
              type: sqlite
              sqlite:
                path: db.sqlite
            prefixes:
              v4: 100.64.0.0/10
              v6: fd7a:115c:a1e0::/48
            derp:
              server:
                enabled: true
                stun_listen_addr: "0.0.0.0:3478"
                private_key_path: derp_server_private.key
            dns:
              override_local_dns: false
              magic_dns: false
            EOF

            headscale serve --config "$CONFIG_FILE" &
            headscale --config "$CONFIG_FILE" preauthkeys create \
              --reusable \
              --tags tag:server \
              --expiration 8760h > "$out"/authkey

            sqlite3 db.sqlite <<EOF > "$out"/authkeys-dump.sql
            .mode insert pre_auth_keys_import
            SELECT * FROM pre_auth_keys;
            EOF
          '';
        };

        services.tailscale = let
          controllers = builtins.attrNames roles.controller.machines;
          noController = controllers == [];
        in {
          enable = true;
          authKeyFile = config.clan.core.vars.generators.${instanceName}.files.authkey.path;
          useRoutingFeatures = "none";
          openFirewall = false;
          extraUpFlags = let
            controllerName = builtins.head controllers;
            server =
              if (machine.name == controllerName)
              then "http://localhost:${toString roles.controller.machines.${machine.name}.settings.port}"
              else "https://${roles.controller.machines.${controllerName}.settings.domain}:443";
          in
            ["--ssh"] ++ lib.optionals (!noController) ["--login-server" server];
        };
      };
    };
  };

  roles.controller = {
    description = "A controller that routes peer traffic. Must be publicly reachable if no proxy is specified.";
    interface = {lib, ...}: {
      options = {
        domain = lib.mkOption {
          type = lib.types.str;
          example = "headscale.example.com";
          description = ''
            Domain name of the headscale server.
          '';
        };
        port = lib.mkOption {
          type = lib.types.int;
          example = "3009";
          description = ''
            Port of the headscale server.
          '';
        };
        interface = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          example = "mycelium";
          default = null;
          description = ''
            Interface the headscale server is listening on.
          '';
        };
        globalNameservers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          example = ["1.1.1.1" "https://dns.nextdns.io/abcdef"];
          description = ''
            Extra public nameservers to add to nameserver.global
          '';
        };
        aclConfig = lib.mkOption {
          type = with lib.types; let
            mkBoundedJson = depth: let
              baseType = [
                bool
                int
                float
                str
                path
              ];
              recType = oneOf (
                baseType
                ++ [
                  (attrsOf (mkBoundedJson (depth - 1)))
                  (listOf (mkBoundedJson (depth - 1)))
                ]
              );
            in
              if depth > 0
              then recType
              else oneOf baseType;
          in
            mkBoundedJson 5;
          description = ''
            Contents of HuJSON file containing ACL policies.
          '';
        };
      };
    };
    perInstance = {
      settings,
      instanceName,
      roles,
      ...
    }: {
      nixosModule = {
        config,
        pkgs,
        lib,
        ...
      }: let
        dnsRecords = "/run/headscale/dns-records/records.json";
      in {
        networking.firewall =
          if (settings.interface == null)
          then {
            allowedTCPPorts = [settings.port];
          }
          else {
            interfaces.${settings.interface}.allowedTCPPorts = [settings.port];
          };

        services = {
          headscale = {
            enable = true;
            address = "0.0.0.0";
            port = settings.port;
            settings = {
              server_url = "https://${settings.domain}";
              dns = let
              in {
                magic_dns = true;
                base_domain = config.clan.core.settings.domain;
                extra_records_path = dnsRecords;
                nameservers = {
                  global = settings.globalNameservers;
                };
              };
              logtail.enabled = false;
              log.level = "debug";
              policy.path = let
                aclHuJson = ''
                  // Headscale ACL Policy - Generated by Clan
                  ${builtins.toJSON settings.aclConfig}
                '';
              in
                pkgs.writeText "acl-policy.hujson" aclHuJson;
            };
          };
        };

        systemd = let
          #NOTE: do not use /run/headscale as it's live time depends on headscale.service
          serverMachines = builtins.attrNames roles.server.machines;
        in {
          tmpfiles.rules = [
            "f ${dnsRecords} 0644 headscale headscale - []"
          ];

          services = {
            headscale-dns-records = let
              #TODO: calculate from exports
              endpointMappings = [
                {
                  endpoint = "vault.mcloud";
                  machine = "brain";
                }
              ];

              # Import Python script using writePython3Bin
              dnsGenScript = pkgs.writers.writePython3Bin "dns-gen" {} (builtins.readFile ./dns_gen.py);

              # Build the shell commands for all endpoints
              generateCommands = builtins.concatStringsSep "\n" (map (m: ''
                  echo "$MACHINES" | ${dnsGenScript}/bin/dns-gen -e "${m.endpoint}" -m "${m.machine}"
                '')
                endpointMappings);
            in {
              description = "Generate DNS records from Headscale machines";

              after = ["headscale.service"];
              requires = ["headscale.service"];
              wantedBy = ["multi-user.target"];

              restartTriggers = [
                (builtins.hashString "sha256" (builtins.toJSON endpointMappings))
              ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                RuntimeDirectory = "headscale/dns-records";
                RuntimeDirectoryMode = "0755";
              };

              path = with pkgs; [jq headscale];

              script = ''
                set -euo pipefail

                sleep 2

                MACHINES=$(headscale nodes list --output json-line)

                {
                  ${generateCommands}
                } | jq -s 'add' > ${dnsRecords}

                echo "Generated DNS records at ${dnsRecords}"
              '';
            };

            headscale-ensure-authkey = {
              enable = true;
              description = "Ensure Headscale authkey for network nodes exists";
              after = ["headscale.service"];
              requires = ["headscale.service"];
              wantedBy = ["multi-user.target"];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = "headscale";
                Group = "headscale";
              };

              script = let
                db = "/var/lib/headscale/db.sqlite";
              in ''
                [ ! -f ${db} ] && { echo "Database not found"; exit 1; }

                ${pkgs.sqlite}/bin/sqlite3 ${db} <<'SQL'
                DROP TABLE IF EXISTS pre_auth_keys_import;
                CREATE TABLE pre_auth_keys_import (
                  id integer,
                  key text,
                  prefix text,
                  hash blob,
                  user_id integer,
                  reusable numeric,
                  ephemeral numeric DEFAULT false,
                  used numeric DEFAULT false,
                  tags text,
                  created_at datetime,
                  expiration datetime
                );
                SQL

                ${lib.concatMapStringsSep "\n" (machine: let
                    query = clanLib.getPublicValue {
                      flake = directory;
                      machine = machine;
                      generator = instanceName;
                      file = "authkeys-dump.sql";
                    };
                  in ''
                    ${pkgs.sqlite}/bin/sqlite3 ${db} <<'SQL'
                    ${query}
                    SQL
                  '')
                  serverMachines}

                ${pkgs.sqlite}/bin/sqlite3 ${db} <<'SQL'
                BEGIN;
                INSERT INTO pre_auth_keys (key, prefix, hash, user_id, reusable, ephemeral, used, tags, created_at, expiration)
                SELECT key, prefix, hash, user_id, reusable, ephemeral, used, tags, created_at, expiration
                FROM pre_auth_keys_import
                WHERE prefix NOT IN (SELECT prefix FROM pre_auth_keys);
                DROP TABLE pre_auth_keys_import;
                COMMIT;
                SQL
              '';
            };
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
    perInstance = {roles, ...}: {
      nixosModule = {lib, ...}: {
        services.nginx = let
          controller = builtins.head (builtins.attrNames roles.controller.machines);
          controllerSettings = roles.controller.machines.${controller}.settings;
          ways2ConnectToController = how2ConnectTo controller;
        in {
          enable = true;
          recommendedProxySettings = true;

          upstreams."headscale-backend" = {
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
                  "${address}:${builtins.toString controllerSettings.port}"
                  {
                    max_fails = 3;
                    fail_timeout = "30s";
                    backup = i > 0;
                  }
              )
              ways2ConnectToController
            );
          };

          virtualHosts."${controllerSettings.domain}" = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://headscale-backend";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_redirect http:// https://;
                proxy_buffering off;
                proxy_next_upstream error timeout http_502 http_503 http_504;
              '';
            };
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
                nofControllers = getNof "controller";
                nofCA = getNof "ca";
                nofDNS = getNof "dns";
                nofProxy = getNof "proxy";
              in [
                {
                  assertion = nofControllers <= 1;
                  message = ''
                    Instance ${instanceName} of service tailscale had ${nofControllers} machines of role "controller" specified when it should at most 1.
                  '';
                }
                {
                  assertion = nofCA <= 1;
                  message = ''
                    Instance ${instanceName} of service tailscale had ${nofCA} machines of role "ca" specified when it should be at most 1.
                  '';
                }
                {
                  assertion = nofDNS <= 1;
                  message = ''
                    Instance ${instanceName} of service tailscale had ${nofDNS} machines of role "dns" specified when it should be at most 1.
                  '';
                }
                {
                  assertion = nofProxy <= 1;
                  message = ''
                    Instance ${instanceName} of service tailscale had ${nofProxy} machines of role "proxy" specified when it should be at most 1.
                  '';
                }
                {
                  assertion = nofCA < 1 || nofControllers > 0;
                  message = ''
                    Instance ${instanceName} of service tailscale needs to specify a controller if a CA is to be used.
                  '';
                }
                {
                  assertion = nofDNS < 1 || nofControllers > 0;
                  message = ''
                    Instance ${instanceName} of service tailscale needs to specify a controller if a Nameserver is to be used.
                  '';
                }
                {
                  assertion = nofProxy < 1 || nofControllers > 0;
                  message = ''
                    Instance ${instanceName} of service tailscale needs to specify a controller if a Proxy is to be used.
                  '';
                }
              ]
          )
          instances);
    };
  };
}
