{
  imports = [
    ../../modules/hcloud.nix
    # ../../modules/vaultwarden.nix
  ];

  config = {
    services.couchdb = {
      enable = true;
      bindAddress = "0.0.0.0";
      adminPass = "-pbkdf2:sha256-3628740c00be85908aa3f93c97c67c142d96a61de2f4e4e7e4ee2bf8b80237bd,779331e0029319875fd5850994f360b1,600000";
    };
  };
}
