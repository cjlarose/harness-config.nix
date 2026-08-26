# The opencode environment wrapper, as a pure function.
#
# opencode ships a Claude Code compatibility layer: with no opencode-native file
# present it silently falls back to Claude's, reading the project CLAUDE.md when
# there is no AGENTS.md, ~/.claude/CLAUDE.md when there is no
# ~/.config/opencode/AGENTS.md, and ~/.claude/skills unconditionally. That is a
# convenience for someone migrating off Claude Code, but on a host that runs
# both agents deliberately it is a leak: opencode picks up Claude's global
# prompt and Claude's skills as if they were its own.
#
# opencode gates each half of that fallback behind an environment variable
# (https://opencode.ai/docs/rules/#claude-code-compatibility), read at startup:
#
#   OPENCODE_DISABLE_CLAUDE_CODE=1         all .claude support
#   OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1  only ~/.claude/CLAUDE.md
#   OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1  only ~/.claude/skills
#
# home-manager's programs.opencode owns the package and settings but not this
# environment, and it cannot come from home.sessionVariables either: those are
# read by the login shell and would then disable Claude's fallbacks for every
# process, not opencode specifically. So it is a package -> package transform,
# same shape as lib.wrapClaudeCode, and lives here as a function taking the
# consumer's pkgs and package rather than as a home-manager module or a
# pre-built package -- this flake never builds opencode itself.
#
# The same wrapper serves opencode v1 (`opencode`) and the v2 beta (`opencode2`)
# via `binName`; both read these variables. The PROMPT gate is a v1 concern --
# v2 dropped the CLAUDE.md fallback and discovers AGENTS.md only -- but setting
# it there is inert, not wrong. The SKILLS gate applies to both.
#
# Usage (in a home-manager config):
#
#   programs.opencode.package = harnessConfig.lib.wrapOpencode {
#     inherit pkgs;
#     package = pkgs.opencode;
#     disableClaudePrompt = true;
#     disableClaudeSkills = true;
#   };
{
  pkgs,
  # The opencode package to wrap. The environment below is layered on top of
  # whatever is named here (the consumer's pkgs.opencode for v1, or a self-built
  # opencode2 for the v2 beta).
  package,
  # The binary to expose. "opencode" for v1, "opencode2" for the v2 beta, so a
  # host can wrap and install both side by side.
  binName ? "opencode",
  # Disable Claude Code compatibility wholesale: neither Claude's prompt files
  # nor Claude's skills are read. Subsumes the two toggles below, so naming it
  # alongside them is redundant rather than conflicting.
  disableClaudeCompat ? false,
  # Disable only the Claude prompt fallback (project CLAUDE.md and
  # ~/.claude/CLAUDE.md); Claude's skills are still read.
  disableClaudePrompt ? false,
  # Disable only the ~/.claude/skills fallback; Claude's prompt files are still
  # read.
  disableClaudeSkills ? false,
}:

let
  inherit (pkgs) lib;

  # An unpatched call returns the package untouched -- no wrapper in the PATH.
  patched = disableClaudeCompat || disableClaudePrompt || disableClaudeSkills;

  wrapped = pkgs.writeShellScriptBin binName ''
    ${lib.optionalString disableClaudeCompat ''
      # Disable Claude Code compatibility wholesale. The :- default lets an
      # explicit OPENCODE_DISABLE_CLAUDE_CODE=0 win as a per-session escape hatch.
      export OPENCODE_DISABLE_CLAUDE_CODE="''${OPENCODE_DISABLE_CLAUDE_CODE:-1}"
    ''}
    ${lib.optionalString disableClaudePrompt ''
      # Drop the Claude prompt fallback (CLAUDE.md) only. The :- default keeps an
      # explicit OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=0 working per session.
      export OPENCODE_DISABLE_CLAUDE_CODE_PROMPT="''${OPENCODE_DISABLE_CLAUDE_CODE_PROMPT:-1}"
    ''}
    ${lib.optionalString disableClaudeSkills ''
      # Drop the ~/.claude/skills fallback only. The :- default keeps an explicit
      # OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=0 working per session.
      export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="''${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS:-1}"
    ''}
    exec ${package}/bin/${binName} "$@"
  '';
in
if patched then wrapped else package
