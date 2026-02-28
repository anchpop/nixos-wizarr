{ config, lib, pkgs, ... }:

let
  cfg = config.services.wizarr;
in {
  options.services.wizarr = {
    enable = lib.mkEnableOption "Wizarr media server invitation manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5690;
      description = "Port for Wizarr to listen on.";
    };

    package = lib.mkPackageOption pkgs "wizarr" { };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for Wizarr.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.wizarr = {
      isSystemUser = true;
      group = "wizarr";
      home = "/var/lib/wizarr";
    };
    users.groups.wizarr = { };

    # The app checks if /data exists and uses /data/database for its SQLite DB.
    # Create that path as a symlink to the proper state directory.
    systemd.tmpfiles.rules = [
      "d /var/lib/wizarr 0750 wizarr wizarr -"
      "L+ /data/database - - - - /var/lib/wizarr"
    ];

    systemd.services.wizarr = {
      description = "Wizarr media server invitation manager";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        WIZARR_PORT = toString cfg.port;
        TZ = config.time.timeZone;
        HOME = "/var/lib/wizarr";
      };

      serviceConfig = {
        Type = "simple";
        User = "wizarr";
        Group = "wizarr";
        StateDirectory = "wizarr";
        CacheDirectory = "wizarr";

        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/wizarr"
          "--bind 0.0.0.0:${toString cfg.port}"
          "--umask 007"
        ];

        Restart = "on-failure";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
