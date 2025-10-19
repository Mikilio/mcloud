{
  config,
  lib,
  ...
}: let
  cfg = config.clan.mcloud.cftunnel;
in {
  options = {
    clan.mcloud.cftunnel = {
      domain = lib.mkOption {
        type = lib.types.str;
        default = "mikilio.com";
        description = "The main domain for subdomains";
      };

      ingress = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          www = "http://localhost:80";
        };
        description = ''
          A set of subdomain names mapped to their corresponding service URLs.
          Subdomains will be prefixed with the domain (e.g., "mail" becomes "mail.mikilio.com").
        '';
      };
    };
  };

  config = let
    tunnelID = config.clan.core.vars.generators.terraform.files.cftunnel_id.value;
  in {
    clan.core.vars.generators.terraform.files.cftunnel_id.secret = false;
    systemd.services."cloudflared-tunnel-${tunnelID}".environment.TUNNEL_EDGE_IP_VERSION = "6";
    services.cloudflared = {
      enable = true;
      tunnels = {
        ${tunnelID} = {
          credentialsFile = config.sops.secrets.cftunnel.path;
          default = "http://localhost:80";
          ingress = let
            ingressRules =
              lib.mapAttrs' (subdomain: service: {
                name = "${subdomain}.${cfg.domain}";
                value = {
                  service = service;
                };
              })
              cfg.ingress;
          in
            ingressRules;
        };
      };
    };
  };
}
