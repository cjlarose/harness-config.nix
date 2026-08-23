# The Claude Code environment wrapper, as a pure function.
#
# home-manager's programs.claude-code already covers the package, settings, MCP
# servers, plugins, hooks and LSP servers. The one thing it does not provide is
# the terminal-facing environment claude needs to render and behave well, which
# is set immediately before exec and so cannot come from home.sessionVariables
# (those are read by the login shell, and each of these has to hold for claude
# specifically -- $TMUX in particular must stay set for everything else in the
# terminal).
#
# That environment is a package -> package transformation, so it lives here as a
# function rather than as a home-manager module or a pre-built package. Taking
# the consumer's `pkgs` and `package` as arguments keeps allowUnfree and the
# nixpkgs channel entirely the consumer's, and means this flake never builds
# claude-code itself.
#
# This used to be duplicated across the consuming home-manager configs, where
# the copies drifted. One definition here.
#
# Usage (in a home-manager config):
#
#   programs.claude-code.package = harnessConfig.lib.wrapClaudeCode {
#     inherit pkgs;
#     package = pkgs.claude-code;
#     trueColorInTmux = true;
#     fullscreenTui = true;
#     toolShell = "${pkgs.bashInteractive}/bin/bash";
#     agentTeams = true;
#   };
#
# home-manager wraps this package again with its own --plugin-dir flags, so the
# final chain is: HM plugin wrapper -> this env wrapper -> claude-code.
{
  pkgs,
  # The UNWRAPPED claude-code package. The patches below are applied on top of
  # whatever is named here (e.g. the consumer's pkgs.claude-code, or a pinned
  # node build on a no-AVX host).
  package,
  # Unset $TMUX for claude only, so it renders in 24-bit color instead of being
  # capped at 256 inside a tmux session.
  trueColorInTmux ? false,
  # Opt into the fullscreen (alt-screen, flicker-free) TUI renderer.
  fullscreenTui ? false,
  # Absolute path to the shell claude runs its Bash tool under, or null to leave
  # it following $SHELL.
  toolShell ? null,
  # Enable the experimental subagent-teams capability.
  agentTeams ? false,
}:

let
  inherit (pkgs) lib;

  # An unpatched call returns the package untouched -- no wrapper in the PATH.
  patched = trueColorInTmux || fullscreenTui || toolShell != null || agentTeams;

  wrapped = pkgs.writeShellScriptBin "claude" ''
    ${lib.optionalString trueColorInTmux ''
      # claude, via chalk, caps its color level at 256 whenever $TMUX is set -- a
      # cap FORCE_COLOR=3 cannot lift. Dropping the variable is what gets 24-bit
      # color inside tmux, and nothing further along in this process reads it.
      unset TMUX
    ''}
    ${lib.optionalString fullscreenTui ''
      # The fullscreen (alt-screen, flicker-free) TUI renderer. There is no CLI
      # flag; the two mechanisms are the settings.json "tui" key and this
      # variable, which the setting's own description calls equivalent. The
      # variable is the stronger of the two -- claude reads it before the setting
      # and before the tmux -CC / Windows-over-SSH auto-disables. The :- default
      # leaves CLAUDE_CODE_NO_FLICKER=0 working as a per-session escape hatch.
      export CLAUDE_CODE_NO_FLICKER="''${CLAUDE_CODE_NO_FLICKER:-1}"
    ''}
    ${lib.optionalString (toolShell != null) ''
      # The shell claude spawns for the Bash tool. Unset, it follows $SHELL, and
      # a `zsh -c` reads ~/.zshenv on every invocation while a `bash -c` reads
      # nothing -- so naming a shell here keeps a login environment out of tool
      # calls. The :- default lets an explicit value win.
      export CLAUDE_CODE_SHELL="''${CLAUDE_CODE_SHELL:-${toolShell}}"
    ''}
    ${lib.optionalString agentTeams ''
      # The experimental subagent-teams gate. The :- default keeps an explicit
      # CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 working as a per-session opt-out.
      export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="''${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-1}"
    ''}
    exec ${package}/bin/claude "$@"
  '';
in
if patched then wrapped else package
