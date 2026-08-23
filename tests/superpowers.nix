# Build-time tests for lib.mkSuperpowersPlugin, exposed as flake checks. Each
# builds the plugin in some mode and asserts a property; the build's own guards
# and line-count tripwires also run, so a bad upstream pin fails these checks.
{ pkgs, mkSuperpowersPlugin }:

let
  # src defaults to harness-config's pinned superpowers input (closed over by the
  # flake), so the tests need only pass pkgs and the mode being exercised.
  base = mkSuperpowersPlugin { inherit pkgs; };
  noHooks = mkSuperpowersPlugin { inherit pkgs; disableHooks = true; };
  noSpecCommits = mkSuperpowersPlugin { inherit pkgs; disableSpecCommits = true; };
in
{
  # Upstream plugin layout survives the copy.
  superpowers-structure = pkgs.runCommand "superpowers-structure" { plugin = base; } ''
    test -f "$plugin/.claude-plugin/plugin.json" || { echo "missing .claude-plugin/plugin.json"; exit 1; }
    test -d "$plugin/skills" || { echo "missing skills/"; exit 1; }
    touch $out
  '';

  # Default build (hooks enabled): the store path is baked into hooks.json and no
  # unresolved CLAUDE_PLUGIN_ROOT reference is left behind.
  superpowers-hooks-baked = pkgs.runCommand "superpowers-hooks-baked" { plugin = base; } ''
    if grep -q 'CLAUDE_PLUGIN_ROOT' "$plugin/hooks/hooks.json"; then
      echo "hooks.json still references CLAUDE_PLUGIN_ROOT"; exit 1
    fi
    grep -qF -- "$plugin" "$plugin/hooks/hooks.json" || { echo "store path not baked into hooks.json"; exit 1; }
    touch $out
  '';

  # disableHooks replaces the hook set with an empty one.
  superpowers-disable-hooks = pkgs.runCommand "superpowers-disable-hooks" { plugin = noHooks; } ''
    got=$(cat "$plugin/hooks/hooks.json")
    [ "$got" = '{"hooks":{}}' ] || { echo "expected empty hookset, got: $got"; exit 1; }
    touch $out
  '';

  # disableSpecCommits rewrites the brainstorming skill's design-doc step.
  superpowers-disable-spec-commits = pkgs.runCommand "superpowers-disable-spec-commits" { plugin = noSpecCommits; } ''
    grep -qF 'Do NOT add it to git' "$plugin/skills/brainstorming/SKILL.md" \
      || { echo "spec-commit patch not applied to brainstorming SKILL.md"; exit 1; }
    touch $out
  '';
}
