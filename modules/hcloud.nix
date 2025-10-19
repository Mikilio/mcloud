{
  config,
  inputs,
  ...
}: {
  imports = with inputs; [
    srvos.nixosModules.server
    srvos.nixosModules.hardware-hetzner-cloud
  ];

  config = {
    clan.core.vars.generators.terraform = let
      tfExports = [
        "hcloud_ipv6"
        "hcloud_ipv4"
      ];
    in {
      files = builtins.listToAttrs (map (var: {
          name = var;
          value.secret = false;
        })
        tfExports);

      script = builtins.concatStringsSep "\n" (builtins.map (var: "touch $out/${var}\n") tfExports);
    };

    systemd.network.networks."10-wan" = {
      # match the interface by name
      # matchConfig.MACAddress = "00:00:00:00:00:00";
      matchConfig.Name = "enp1s0";
      address = [
        "${config.clan.core.vars.generators.terraform.files.hcloud_ipv6.value}/64"
      ];
      # make the routes on this interface a dependency for network-online.target
      linkConfig.RequiredForOnline = "routable";
    };

    networking.nftables.enable = true;
  };
}
