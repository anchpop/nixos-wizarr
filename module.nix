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
    systemd.services.wizarr = {
      description = "Wizarr media server invitation manager";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        WIZARR_PORT = toString cfg.port;
        TZ = config.time.timeZone;
        HOME = "/var/lib/wizarr";
      };

      preStart = ''
        # Run database migrations
        ${cfg.package}/bin/wizarr-migrate db upgrade
      '';

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "wizarr";
        CacheDirectory = "wizarr";

        # Map /data/database -> /var/lib/wizarr so the app finds its database
        BindPaths = "/var/lib/wizarr:/data/database";
        TemporaryFileSystem = "/data:ro";

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
