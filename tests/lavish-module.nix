{ pkgs, home-manager, lavishModule, lavishPackage }:

let
  stubPackage = pkgs.runCommand "lavish-module-stub-package" { } ''
    mkdir -p "$out/bin" "$out/share/lavish-axi/skill"
    touch "$out/bin/lavish-axi"
    touch "$out/share/lavish-axi/skill/SKILL.md"
  '';

  evaluate = lavishConfig: (home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      lavishModule
      {
        home.username = "test";
        home.homeDirectory = "/home/test";
        home.stateVersion = "26.05";
        programs.lavish = lavishConfig;
      }
    ];
  }).config;

  lavishVariables = config:
    pkgs.lib.filterAttrs (name: _: pkgs.lib.hasPrefix "LAVISH_AXI_" name)
      config.home.sessionVariables;

  defaults = evaluate {
    enable = true;
  };

  disabled = evaluate {
    claudeCodeSkill.enable = true;
    opencodeSkill.enable = true;
  };

  noTelemetry = evaluate {
    enable = true;
    disableTelemetry = true;
  };

  configured = evaluate {
    enable = true;
    package = stubPackage;
    host = "127.0.0.2";
    linkHost = "lavish.example.test";
    linkScheme = "https";
    linkPort = "";
    allowedHosts = [
      "lavish.example.test"
      "alias.example.test"
    ];
    port = 4387;
  };

  claudeOnly = evaluate {
    enable = true;
    package = stubPackage;
    claudeCodeSkill.enable = true;
  };

  opencodeOnly = evaluate {
    enable = true;
    package = stubPackage;
    opencodeSkill.enable = true;
  };

  skill = "${stubPackage}/share/lavish-axi/skill/SKILL.md";
in
{
  lavish-module-defaults =
    assert defaults.programs.lavish.package == lavishPackage;
    assert builtins.elem lavishPackage defaults.home.packages;
    assert lavishVariables defaults == { };
    pkgs.runCommand "lavish-module-defaults" { } ''
      touch "$out"
    '';

  lavish-module-disabled =
    assert !(builtins.elem lavishPackage disabled.home.packages);
    assert lavishVariables disabled == { };
    assert disabled.programs.claude-code.skills == { };
    assert disabled.programs.opencode.skills == { };
    pkgs.runCommand "lavish-module-disabled" { } ''
      touch "$out"
    '';

  lavish-module-telemetry-option =
    assert noTelemetry.home.sessionVariables.LAVISH_AXI_TELEMETRY == "0";
    assert !(builtins.hasAttr "LAVISH_AXI_TELEMETRY" defaults.home.sessionVariables);
    pkgs.runCommand "lavish-module-telemetry-option" { } ''
      touch "$out"
    '';

  lavish-module-configured =
    assert builtins.elem stubPackage configured.home.packages;
    assert lavishVariables configured == {
      LAVISH_AXI_HOST = "127.0.0.2";
      LAVISH_AXI_LINK_HOST = "lavish.example.test";
      LAVISH_AXI_LINK_SCHEME = "https";
      LAVISH_AXI_LINK_PORT = "";
      LAVISH_AXI_ALLOWED_HOSTS = "lavish.example.test alias.example.test";
      LAVISH_AXI_PORT = "4387";
    };
    pkgs.runCommand "lavish-module-configured" { } ''
      touch "$out"
    '';

  lavish-module-skill-independence =
    assert claudeOnly.programs.claude-code.skills == { lavish = skill; };
    assert claudeOnly.programs.opencode.skills == { };
    assert opencodeOnly.programs.claude-code.skills == { };
    assert opencodeOnly.programs.opencode.skills == { lavish = skill; };
    pkgs.runCommand "lavish-module-skill-independence" { } ''
      touch "$out"
    '';
}
