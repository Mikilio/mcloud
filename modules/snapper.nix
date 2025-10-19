{
  lib,
  pkgs,
  ...
}: {
  services.snapper = {
    configs.root = {
      SUBVOLUME = "/persistent/storage";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_YEARLY = 0;
      TIMELINE_LIMIT_QUARTERLY = 0;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_WEEKLY = 0;
      TIMELINE_LIMIT_DAILY = 5;
      TIMELINE_LIMIT_HOURLY = 10;
    };
  };
}
