{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.lavish;
  skill = "${cfg.package}/share/lavish-axi/skill/SKILL.md";
in
{
  options.programs.lavish = {
    enable = lib.mkEnableOption "Lavish AXI";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.lib.mkLavishAxi {
        inherit pkgs;
        enableProxySupport = true;
      };
      description = "The Lavish AXI package to install.";
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Opt Lavish out of telemetry by setting LAVISH_AXI_TELEMETRY=0 in
        home.sessionVariables. Off by default, so the upstream telemetry
        behavior is unchanged unless you opt out.
      '';
    };

    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host address exposed as LAVISH_AXI_HOST.";
    };

    linkHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public link host exposed as LAVISH_AXI_LINK_HOST.";
    };

    linkScheme = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "http" "https" ]);
      default = null;
      description = "Public link scheme exposed as LAVISH_AXI_LINK_SCHEME.";
    };

    linkPort = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Public link port exposed as LAVISH_AXI_LINK_PORT. Set this to an empty
        string to omit the port from generated links.
      '';
    };

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Allowed host names exposed as the space-separated
        LAVISH_AXI_ALLOWED_HOSTS value.
      '';
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Listening port exposed as LAVISH_AXI_PORT.";
    };

    claudeCodeSkill.enable = lib.mkEnableOption "the Lavish skill for Claude Code";
    opencodeSkill.enable = lib.mkEnableOption "the Lavish skill for OpenCode";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.sessionVariables =
      lib.optionalAttrs (cfg.disableTelemetry)
        {
          LAVISH_AXI_TELEMETRY = "0";
        }
      // lib.optionalAttrs (cfg.host != null)
        {
          LAVISH_AXI_HOST = cfg.host;
        }
      // lib.optionalAttrs (cfg.linkHost != null) {
        LAVISH_AXI_LINK_HOST = cfg.linkHost;
      }
      // lib.optionalAttrs (cfg.linkScheme != null) {
        LAVISH_AXI_LINK_SCHEME = cfg.linkScheme;
      }
      // lib.optionalAttrs (cfg.linkPort != null) {
        LAVISH_AXI_LINK_PORT = cfg.linkPort;
      }
      // lib.optionalAttrs (cfg.allowedHosts != [ ]) {
        LAVISH_AXI_ALLOWED_HOSTS = lib.concatStringsSep " " cfg.allowedHosts;
      }
      // lib.optionalAttrs (cfg.port != null) {
        LAVISH_AXI_PORT = toString cfg.port;
      };

    programs.claude-code.skills = lib.mkIf cfg.claudeCodeSkill.enable {
      lavish = skill;
    };

    programs.opencode.skills = lib.mkIf cfg.opencodeSkill.enable {
      lavish = skill;
    };
  };
}
