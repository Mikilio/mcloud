{
  config,
  lib,
  pkgs,
  ...
}: let
  storj = {
    bucket = "my-distributed-backups";
    endpoint = "https://gateway.storjshare.io";
    remoteName = "storj-s3";
  };

  # Helper to create a discrete, auto-initializing plaintext job for each state
  mkResticJob = name: state: {
    # 1. Folders from the clan state
    paths = state.folders;

    # 2. Rclone bridge to Storj
    repository = "rclone:${storj.remoteName}:${storj.bucket}/${name}";

    # 3. NO RESTIC PASSWORD
    # Since Storj is encrypted by default, we use 'plaintext' mode.
    # extraOptions are passed to both 'backup' AND 'init'.
    extraOptions = ["id.encryption=plaintext"];

    # 4. Automatic Initialization
    # Since extraOptions contains plaintext, 'restic init' will run without a password.
    initialize = true;

    # 5. Credentials for the Storj S3 Gateway
    environmentFile = config.clan.core.vars.generators.storj.files."storj.env".path;

    rcloneConfig."${storj.remoteName}" = {
      type = "s3";
      provider = "Storj";
      endpoint = storj.endpoint;
      env_auth = true;
    };

    # 6. Lifecycle hooks from clan.core.state
    backupPrepareCommand = state.preBackupCommand;
    backupCleanupCommand = state.postBackupCommand;

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
in {
  # Map over all Clan states to generate individual Restic jobs
  services.restic.backups = lib.mapAttrs mkResticJob config.clan.core.state;

  # Clan Provider Interface
  clan.core.backups.providers.restic = {
    list = "restic-list";
    create = "restic-create";
    restore = "restic-restore";
  };

  # Provider CLI Utilities for Clan
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "restic-create";
      runtimeInputs = [config.systemd.package];
      text = ''
        ${lib.concatMapStringsSep "\n" (name: ''
          systemctl start restic-backups-${name}.service
        '') (lib.attrNames config.clan.core.state)}
      '';
    })

    (pkgs.writeShellApplication {
      name = "restic-list";
      runtimeInputs = [pkgs.restic pkgs.jq];
      text = ''
        set -a; source "${config.clan.core.vars.generators.storj.files."storj.env".path}"; set +a
        ${lib.concatMapStringsSep "\n" (name: ''
          restic -r rclone:${storj.remoteName}:${storj.bucket}/${name} snapshots --json | \
            jq '[.[] | {name: ("${name}::" + .id), time: .time}]'
        '') (lib.attrNames config.clan.core.state)} | jq -s 'add // []'
      '';
    })

    (pkgs.writeShellApplication {
      name = "restic-restore";
      runtimeInputs = [pkgs.restic];
      text = ''
        set -a; source "${config.clan.core.vars.generators.storj.files."storj.env".path}"; set +a
        STATE_NAME=$(echo "$NAME" | cut -d':' -f1)
        SNAPSHOT_ID=$(echo "$NAME" | cut -d':' -f3)

        restic -r "rclone:${storj.remoteName}:${storj.bucket}/$STATE_NAME" \
          restore "$SNAPSHOT_ID" --target /
      '';
    })
  ];

  # Storj S3 Credentials Generator
  clan.core.vars.generators.storj = {
    files."storj.env" = {};
    script = ''
      # Note: These are S3-compatible credentials provided by Storj Console
      echo "AWS_ACCESS_KEY_ID=..." >> "$out/storj.env"
      echo "AWS_SECRET_ACCESS_KEY=..." >> "$out/storj.env"
    '';
  };
}
