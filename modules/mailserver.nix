{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.mailserver.nixosModule
  ];

  config = let
    accounts = {
      admin.aliases = ["kilian.mio@mikilio.com" "security@mikilio.com"];
      victoria = {};
      info.aliases = ["contact@mikilio.com"];
      no-reply = {
        sendOnly = true;
        sendOnlyRejectMessage = ''
          Subject: Re: Your Email to no-reply@mikilio.com – How to Reach Us

          Hello,

          This is an automated response: You've reached our no-reply@mikilio.com address, which is reserved for automated notifications only and isn't monitored for incoming replies.

          To connect with Mikilio Consulting, please use:
          - General inquiries: info@mikilio.com
          - Direct contact: kilian.mio@mikilio.com
          - Our website: mikilio.com/contact (for forms or scheduling)

          Thank you for understanding.
        '';
      };
    };
  in {
    clan.core.vars.generators = {
      dkim = let
        cfg = config.mailserver;
        domains = map (dom: "${dom}.${cfg.dkimSelector}") cfg.domains;
      in {
        files = let
          keys =
            map (domain: {
              name = "${domain}.key";
              value = {
                secret = true;
                owner = config.services.rspamd.user;
                group = config.services.rspamd.group;
              };
            })
            domains;
          records =
            map (domain: {
              name = "${domain}.txt";
              value.secret = false;
            })
            domains;
        in
          builtins.listToAttrs (keys ++ records);

        script = builtins.concatStringsSep "\n" (builtins.map (domain:
          #bash
          ''
            rspamadm dkim_keygen \
            --domain "${domain}" \
            --selector "${cfg.dkimSelector}" \
            --type "${cfg.dkimKeyType}" \
            --bits ${toString cfg.dkimKeyBits} \
            --privkey "$out"/${domain}.key > "$out"/${domain}.txt
          '')
        domains);
        runtimeInputs = [pkgs.rspamd];
      };
      email-users = let
        users = builtins.attrNames accounts;
      in {
        files = let
          passwords =
            map (user: {
              name = user;
              value.secret = true;
            })
            users;
          hashes =
            map (user: {
              name = "${user}_hash";
              value.secret = false;
            })
            users;
        in
          builtins.listToAttrs (passwords ++ hashes);

        share = true;
        script = builtins.concatStringsSep "\n" (builtins.map (var:
          #bash
          ''
            pwgen 20 1 | tr -d '\n' > "$out"/${var}
            mkpasswd -sm bcrypt < "$out"/${var} | tr -d "\n" > "$out"/${var}_hash
          '')
        users);
        runtimeInputs = [pkgs.mkpasswd pkgs.pwgen pkgs.coreutils];
      };
    };

    sops.secrets = with builtins; (listToAttrs (map (file: {
        name = "vars/${file.generatorName}/${file.name}";
        value = {
          path = "${config.mailserver.dkimKeyDirectory}/${file.name}";
        };
      })
      (filter (file: lib.hasSuffix ".key" file.name) (attrValues config.clan.core.vars.generators.dkim.files))));

    mailserver = {
      enable = true;
      stateVersion = 3;
      fqdn = "mail.mikilio.com";
      domains = ["mikilio.com"];

      loginAccounts = builtins.listToAttrs (lib.mapAttrsToList (name: value: let
          address = "${name}@mikilio.com";
        in {
          name = address;
          value =
            value
            // {
              hashedPassword = config.clan.core.vars.generators.email-users.files."${name}_hash".value;
            };
        })
        accounts);

      dmarcReporting.enable = true;

      x509.useACMEHost = config.mailserver.fqdn;
    };

    systemd.services.rspamd.serviceConfig = {
      ExecStartPre = lib.mkForce [];
      ReadWritePaths = lib.mkForce [];
    };

    services = {
      radicale = with lib; let
        mailAccounts = config.mailserver.loginAccounts;
        htpasswd = pkgs.writeText "radicale.users" (
          concatStrings
          (flip mapAttrsToList mailAccounts (
            mail: user:
              mail + ":" + user.hashedPassword + "\n"
          ))
        );
      in {
        enable = true;
        settings = {
          auth = {
            type = "htpasswd";
            htpasswd_filename = "${htpasswd}";
            htpasswd_encryption = "bcrypt";
          };
        };
      };
      roundcube = {
        enable = true;
        # this is the url of the vhost, not necessarily the same as the fqdn of
        # the mailserver
        hostName = "mail.mikilio.com";
        extraConfig = ''
          $config['smtp_host'] = "ssl://%h";
          $config['imap_host'] = "ssl://${config.mailserver.fqdn}:993";
          $config['smtp_user'] = "%u";
          $config['smtp_pass'] = "%p";
        '';
      };
      nginx = {
        enable = true;
        virtualHosts = {
          "cal.mikilio.com" = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://localhost:5232/";
              extraConfig = ''
                proxy_set_header  X-Script-Name /;
                proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_pass_header Authorization;
              '';
            };
          };
        };
      };
    };

    networking.firewall.allowedTCPPorts = [80 443];
    security.acme = {
      acceptTerms = true;
      defaults.email = "security@mikilio.com";
    };

    system.stateVersion = "25.05";
  };
}
