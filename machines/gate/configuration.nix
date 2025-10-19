{
  config,
  lib,
  ...
}: {
  imports = [
    ../../modules/hcloud.nix
    ../../modules/mailserver.nix
    ../../modules/public_gateway.nix
  ];

  nixpkgs.hostPlatform.system = "x86_64-linux";
}
