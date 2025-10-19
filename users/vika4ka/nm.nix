{
    MikilioLab = {
    connection = {
      id = "MikilioLab";
      interface-name = "wlp1s0";
      type = "wifi";
      uuid = "6187634f-2758-4f23-9f5d-36dd14438e00";
    };
    ipv4 = {
      method = "auto";
    };
    ipv6 = {
      addr-gen-mode = "default";
      method = "auto";
    };
    proxy = { };
    wifi = {
      hidden = "true";
      ssid = "MikilioLab";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk-flags = "1";
    };
  };
  # eduroam = {
  #   "802-1x" = {
  #     anonymous-identity = "anonymous";
  #     domain-suffix-match = "radius.lrz.de";
  #     eap = "peap;";
  #     identity = "ga84tet@eduroam.mwn.de";
  #     password-flags = "1";
  #     phase2-auth = "mschapv2";
  #   };
  #   connection = {
  #     id = "eduroam";
  #     interface-name = "wlp1s0";
  #     type = "wifi";
  #     uuid = "082521d4-67c1-4866-8c85-a3593a5ec026";
  #   };
  #   ipv4 = {
  #     method = "auto";
  #   };
  #   ipv6 = {
  #     addr-gen-mode = "stable-privacy";
  #     method = "auto";
  #   };
  #   proxy = { };
  #   wifi = {
  #     mode = "infrastructure";
  #     ssid = "eduroam";
  #   };
  #   wifi-security = {
  #     key-mgmt = "wpa-eap";
  #   };
  # };
  "Mi A3" = {
    connection = {
      id = "Mi A3";
      interface-name = "wlp1s0";
      type = "wifi";
      uuid = "9470c9eb-44ea-478d-b112-9b81c02caefa";
    };
    ipv4 = {
      method = "auto";
    };
    ipv6 = {
      addr-gen-mode = "default";
      method = "auto";
    };
    proxy = {};
    wifi = {
      mode = "infrastructure";
      ssid = "Mi A3";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk-flags = "1";
    };
  };
  PHX-5G-Guest = {
    connection = {
      id = "PHX-5G-Guest";
      type = "wifi";
      uuid = "eb9e81aa-2b05-4e5c-af22-5746b2f5e7db";
    };
    ipv4 = {
      method = "auto";
    };
    ipv6 = {
      addr-gen-mode = "stable-privacy";
      method = "auto";
    };
    proxy = {};
    wifi = {
      mode = "infrastructure";
      ssid = "PHX-5G-Guest";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk-flags = "1";
    };
  };
  WLAN-260804 = {
    connection = {
      id = "WLAN-260804";
      interface-name = "wlp1s0";
      type = "wifi";
      uuid = "8326f95a-411b-400c-9e18-3105421a2ac0";
    };
    ipv4 = {
      method = "auto";
    };
    ipv6 = {
      addr-gen-mode = "default";
      method = "auto";
    };
    proxy = {};
    wifi = {
      mode = "infrastructure";
      ssid = "WLAN-260804";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk-flags = "1";
    };
  };
}
