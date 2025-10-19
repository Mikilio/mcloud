{
  config,
  pkgs,
  lib,
  ...
}: let
  clanCfg = config.clan.core.state.persistence;

  mkScript = name: script:
    pkgs.writeShellScript name (
      if script != null
      then script
      else "exit 0"
    );

  mkWrapper = name: script: {
    source = "${script}";
    owner = "root";
    group = "duplicati";
    permissions = "u+rx,g+x,o-rwx";
    setuid = true;
  };

  # Create the actual scripts that will run as root
  preBackupScript = mkScript "preBackupScript" clanCfg.preBackupScript;
  postBackupScript = mkScript "postBackupScript" clanCfg.postBackupScript;
  preRestoreScript = mkScript "preRestoreScript" clanCfg.preRestoreScript;
  postRestoreScript = mkScript "postRestoreScript" clanCfg.postRestoreScript;

  # Combined before script that checks DUPLICATI__OPERATIONNAME
  beforeScript = pkgs.writeShellScript "duplicati-before" ''
    if [ "$DUPLICATI__OPERATIONNAME" == "Backup" ]; then
      /run/wrappers/bin/duplicati-pre-backup
    elif [ "$DUPLICATI__OPERATIONNAME" == "Restore" ]; then
      /run/wrappers/bin/duplicati-pre-restore
    fi
  '';

  # Combined after script that checks DUPLICATI__OPERATIONNAME
  afterScript = pkgs.writeShellScript "duplicati-after" ''
    if [ "$DUPLICATI__OPERATIONNAME" == "Backup" ]; then
      /run/wrappers/bin/duplicati-post-backup
    elif [ "$DUPLICATI__OPERATIONNAME" == "Restore" ]; then
      /run/wrappers/bin/duplicati-post-restore
    fi
  '';
in {
  services.duplicati = {
    enable = true;

    parameters = ''
      --run-script-before-required=${beforeScript}
      --run-script-after=${afterScript}
    '';
  };

  # Create setuid wrappers that run as root but are only executable by duplicati and root
  security.wrappers = {
    duplicati-pre-backup = mkWrapper "duplicati-pre-backup" preBackupScript;
    duplicati-post-backup = mkWrapper "duplicati-post-backup" postBackupScript;
    duplicati-pre-restore = mkWrapper "duplicati-pre-restore" preRestoreScript;
    duplicati-post-restore = mkWrapper "duplicati-post-restore" postRestoreScript;
  };
}
