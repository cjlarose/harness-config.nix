# Build-time tests for lib.wrapClaudeCode, exposed as flake checks and run by
# `nix flake check`. Each returns a derivation that builds iff the property
# holds. A free stub package stands in for the wrapped claude-code build, so the
# tests need no allowUnfree and no network.
{ pkgs, wrapClaudeCode }:

let
  inherit (pkgs) lib;

  stubClaude = pkgs.writeShellScriptBin "claude" ''
    printf '%s\n' "$CLAUDE_CODE_DISABLE_AUTO_MEMORY"
  '';

  # bin/claude of a wrapped result, for content assertions.
  scriptOf = args:
    "${wrapClaudeCode ({ inherit pkgs; package = stubClaude; } // args)}/bin/claude";
in
{
  # No toggle requested -> the input package is returned untouched (no wrapper
  # derivation in the PATH). Relies on Nix derivation equality: the identity
  # branch returns the very package passed in.
  wrap-identity =
    let r = wrapClaudeCode { inherit pkgs; package = stubClaude; };
    in
    pkgs.runCommand "wrap-identity" { } ''
      ${lib.optionalString (r != stubClaude)
        "echo 'expected unpatched call to return package unchanged'; exit 1"}
      touch $out
    '';

  # Requested toggles appear; unrequested ones do not.
  wrap-selective = pkgs.runCommand "wrap-selective"
    { script = scriptOf { trueColorInTmux = true; agentTeams = true; }; } ''
    present() { grep -q -- "$1" "$script" || { echo "missing: $1"; exit 1; }; }
    absent()  { if grep -q -- "$1" "$script"; then echo "unexpected: $1"; exit 1; fi; }

    present 'unset TMUX'
    present 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'
    absent  'CLAUDE_CODE_NO_FLICKER'   # fullscreenTui not requested
    absent  'CLAUDE_CODE_SHELL'        # toolShell not requested
    absent  'CLAUDE_CODE_DISABLE_AUTO_MEMORY'
    touch $out
  '';

  # An invocation-level check: an explicit 0 must override the wrapper default.
  wrap-auto-memory-override = pkgs.runCommand "wrap-auto-memory-override"
    { script = scriptOf { disableAutoMemory = true; }; } ''
    actual="$(CLAUDE_CODE_DISABLE_AUTO_MEMORY=0 "$script")"
    test "$actual" = 0 || {
      echo "expected CLAUDE_CODE_DISABLE_AUTO_MEMORY=0, got: $actual"
      exit 1
    }
    touch $out
  '';

  # toolShell interpolates the given path, and every toggle composes.
  wrap-all = pkgs.runCommand "wrap-all"
    {
      script = scriptOf {
        trueColorInTmux = true;
        fullscreenTui = true;
        toolShell = "/run/current-system/sw/bin/bash";
        agentTeams = true;
        disableAutoMemory = true;
      };
    } ''
    for needle in 'unset TMUX' 'CLAUDE_CODE_NO_FLICKER' \
                   'CLAUDE_CODE_SHELL' '/run/current-system/sw/bin/bash' \
                   'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' \
                   'CLAUDE_CODE_DISABLE_AUTO_MEMORY'; do
      grep -q -- "$needle" "$script" || { echo "missing: $needle"; exit 1; }
    done
    touch $out
  '';
}
