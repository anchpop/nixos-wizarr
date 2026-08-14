{ config, lib, pkgs, ... }:

let
  cfg = config.services.wizarr;

  stepType = lib.types.submodule {
    options = {
      title = lib.mkOption {
        type = lib.types.str;
        description = "Step title, shown in the wizard's progress chrome.";
      };

      markdown = lib.mkOption {
        type = lib.types.lines;
        description = ''
          Step body. Wizarr's flavoured markdown: `|||` delimits a card,
          `{{ widget:button url="..." text="..." }}` renders a button (a bare
          word for `url` resolves against the wizard context, e.g.
          `external_url` for the media server's public URL), and
          `{{ widget:recently_added_media }}` embeds a library preview.
        '';
      };

      category = lib.mkOption {
        type = lib.types.enum [ "pre_invite" "post_invite" ];
        default = "post_invite";
        description = ''
          Whether the step is shown before the invite is accepted
          (`pre_invite`) or after the account exists (`post_invite`).
        '';
      };

      requireInteraction = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require the user to interact with the step before continuing.";
      };
    };
  };

  stepsSpec = pkgs.writeText "wizarr-wizard-steps.json" (builtins.toJSON cfg.wizardSteps);
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

    wizardSteps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf stepType);
      default = { };
      example = lib.literalExpression ''
        {
          jellyfin = [
            {
              title = "How to watch";
              markdown = '''
                Open <https://watch.example.com> in any browser.
              ''';
            }
          ];
        }
      '';
      description = ''
        Onboarding wizard steps, keyed by media server type (`jellyfin`,
        `plex`, `emby`, …).

        Wizarr seeds these steps into its database from bundled markdown on
        first run and never rewrites them afterwards, so its own model is that
        onboarding copy is edited in the admin UI. Setting this option takes
        that over for the listed server types: the steps are reconciled into
        the database on every service start, so edits made in the admin UI for
        those server types are reverted at the next restart. Server types not
        listed here keep Wizarr's defaults and stay editable in the UI.
      '';
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
        FLASK_SKIP_SCHEDULER = "true";
      };

      preStart = ''
        # Apply Alembic database migrations
        ${cfg.package}/bin/wizarr-migrate db upgrade
      '' + lib.optionalString (cfg.wizardSteps != { }) ''

        # Reconcile declaratively-defined wizard steps into the database.
        # Must run after migrations: it writes the wizard_step table directly.
        ${pkgs.python3}/bin/python3 ${./sync-wizard-steps.py} \
          ${stepsSpec} /var/lib/wizarr/database.db
      '';

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
