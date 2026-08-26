# Build-time tests for lib.wrapOpencode, exposed as flake checks and run by
# `nix flake check`. Each returns a derivation that builds iff the property
# holds. A free stub package stands in for opencode, so the tests need no
# allowUnfree and no network.
{ pkgs, wrapOpencode }:

let
  inherit (pkgs) lib;

  stubOpencode = pkgs.writeShellScriptBin "opencode" "echo stub";

  # bin/<binName> of a wrapped result, for content assertions.
  scriptOf = args:
    let
      binName = args.binName or "opencode";
      r = wrapOpencode ({ inherit pkgs; package = stubOpencode; } // args);
    in
    "${r}/bin/${binName}";
in
{
  # No toggle requested -> the input package is returned untouched (no wrapper
  # derivation in the PATH). Relies on Nix derivation equality: the identity
  # branch returns the very package passed in.
  wrap-opencode-identity =
    let r = wrapOpencode { inherit pkgs; package = stubOpencode; };
    in
    pkgs.runCommand "wrap-opencode-identity" { } ''
      ${lib.optionalString (r != stubOpencode)
        "echo 'expected unpatched call to return package unchanged'; exit 1"}
      touch $out
    '';

  # Requested toggles appear; unrequested ones do not.
  wrap-opencode-selective = pkgs.runCommand "wrap-opencode-selective"
    { script = scriptOf { disableClaudeSkills = true; }; } ''
    present() { grep -q -- "$1" "$script" || { echo "missing: $1"; exit 1; }; }
    absent()  { if grep -q -- "$1" "$script"; then echo "unexpected: $1"; exit 1; fi; }

    present 'OPENCODE_DISABLE_CLAUDE_CODE_SKILLS'
    absent  'OPENCODE_DISABLE_CLAUDE_CODE_PROMPT'   # disableClaudePrompt not requested
    # The master gate is a distinct variable; a substring match would false-match
    # the granular ones, so anchor on the export of exactly that name.
    absent  'OPENCODE_DISABLE_CLAUDE_CODE="'        # disableClaudeCompat not requested
    touch $out
  '';

  # Every toggle composes, and binName renames the exposed binary.
  wrap-opencode-all = pkgs.runCommand "wrap-opencode-all"
    {
      script = scriptOf {
        binName = "opencode2";
        disableClaudeCompat = true;
        disableClaudePrompt = true;
        disableClaudeSkills = true;
      };
    } ''
    for needle in 'OPENCODE_DISABLE_CLAUDE_CODE="' \
                  'OPENCODE_DISABLE_CLAUDE_CODE_PROMPT' \
                  'OPENCODE_DISABLE_CLAUDE_CODE_SKILLS' \
                  'exec ' 'bin/opencode2'; do
      grep -q -- "$needle" "$script" || { echo "missing: $needle"; exit 1; }
    done
    touch $out
  '';

  # binName exposes the wrapped binary under the v2 name.
  wrap-opencode-binname = pkgs.runCommand "wrap-opencode-binname"
    {
      drv = wrapOpencode {
        inherit pkgs;
        package = stubOpencode;
        binName = "opencode2";
        disableClaudeSkills = true;
      };
    } ''
    test -x "$drv/bin/opencode2" || { echo "missing bin/opencode2"; exit 1; }
    touch $out
  '';
}
