{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.stylix.nixosModules.stylix
  ];

  stylix = {
    enable = true;
    enableReleaseChecks = false;
    homeManagerIntegration = {
      autoImport = true;
      followSystem = true;
    };

    image = ./assets/wallpapers/default.jpg;

    polarity = "light";

    cursor = {
      package = pkgs.rose-pine-cursor;
      name = "BreezeX-RosePine-Linux";
      size = 32;
    };

    icons = {
      enable = true;
      package = pkgs.beauty-line-icon-theme;
      light = "BeautyLine";
      dark = "BeautyLine";
    };

    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };

      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };

      monospace = {
        package = pkgs.nerd-fonts.hack;
        name = "Hack";
      };

      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
