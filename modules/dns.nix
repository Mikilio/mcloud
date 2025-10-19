{pkgs, ...}: {
  networking.firewall.interfaces.mycelium = {
    allowedTCPPorts = [1053];
    allowedUDPPorts = [1053];
  };
  services.bind = {
    enable = true;

    # Networks allowed to use BIND as a recursive resolver
    cacheNetworks = [
      "127.0.0.0/8" # localhost
      "::1/128" # localhost IPv6
      "100.64.0.0/10" # Tailscale IPv4 CGNAT range
      "fd7a:115c:a1e0::/48" # Tailscale IPv6 network
      "400::/7" # Mycelium IPv6 range
    ];

    zones = {
      "mcloud" = {
        master = true;
        allowQuery = [
          "127.0.0.0/24"
          "::1/128"
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
          "400::/7"
        ];
        file = pkgs.writeText "zone-internal" ''
          $ORIGIN mcloud.
          $TTL 3600
          @     IN SOA  ns.mcloud. admin.mcloud. 1 7200 3600 1209600 3600
                IN NS   ns.mcloud.
          ns    IN AAAA 4d1:171e:aa9d:8235:eb5e:2a55:66a1:8046   ; DNS server

          vault IN A    100.64.0.1
          vault IN AAAA fd7a:115c:a1e0::1
          notes IN A    100.64.0.1
          notes IN AAAA fd7a:115c:a1e0::1
        '';
      };
    };
  };
}
