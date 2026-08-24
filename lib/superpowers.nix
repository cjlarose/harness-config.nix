# obra/superpowers as a force-loadable Claude Code plugin, built from upstream's
# source with optional customizations applied on top.
#
# Upstream already ships the plugin layout (.claude-plugin/plugin.json, skills/,
# hooks/), so this is a copy with edits rather than a build. The customizations
# are driven by arguments rather than baked in, so a consumer opts into them.
#
# Every edit is --replace-fail or an explicit guard, so an upstream rewording
# breaks the BUILD rather than silently shipping unmodified text. The line-count
# tripwires cover the opposite failure -- an upstream release that ADDS commit
# language, which no search-and-replace can detect on its own. When one fires,
# read the upstream diff and re-derive the strings; do not just bump the count.
#
# Usage (in a home-manager config, on home-manager >= 26.05 where
# programs.claude-code.plugins exists):
#
#   programs.claude-code.plugins = [
#     (harnessConfig.lib.mkSuperpowersPlugin {
#       inherit pkgs;
#       disableHooks = true;
#       disableSpecCommits = true;
#     })
#   ];
#
# The same build serves opencode via its /skills subdir:
#
#   programs.opencode.settings.skills.paths =
#     [ "${harnessConfig.lib.mkSuperpowersPlugin { inherit pkgs; }}/skills" ];
{
  pkgs,
  # Upstream's obra/superpowers source tree. Defaults to harness-config's own
  # pinned input (see flake.nix); a consumer may override to pin their own.
  src,
  # Ship the plugin with an empty hook set, replacing upstream's hooks/hooks.json.
  # Upstream registers a SessionStart hook that injects using-superpowers into
  # every session; this switches that off.
  disableHooks ? false,
  # Patch the brainstorming skill so it does not instruct committing the design
  # doc to git.
  disableSpecCommits ? false,
}:

let
  inherit (pkgs) lib;

  # The literal text "${CLAUDE_PLUGIN_ROOT}" to search for. Built in a normal
  # double-quoted string where \${ is an unambiguous escape; writing it inline in
  # the '' block below collides with Nix's own '' and ''${ escapes.
  pluginRootVar = "\${CLAUDE_PLUGIN_ROOT}";
in
pkgs.runCommand "superpowers-plugin"
{
  inherit src;
  meta = {
    description = "obra/superpowers skills library, packaged as a Claude Code plugin";
    homepage = "https://github.com/obra/superpowers";
    license = lib.licenses.mit;
  };
}
  ''
    cp -r "$src" "$out"
    chmod -R u+w "$out"

    # Guard before either branch: both of them assume hook registration lives in
    # this file, so if upstream moves it, the disable branch would write a stray
    # no-op while the real hook keeps firing, and the substitute branch would
    # leave an unresolved path behind.
    [ -f "$out/hooks/hooks.json" ] \
      || { echo "hooks/hooks.json is gone; upstream moved hook registration -- re-check this build" >&2; exit 1; }

    ${
      if disableHooks then ''
        grep -q '"SessionStart"' "$out/hooks/hooks.json" \
          || { echo "hooks.json no longer registers SessionStart; re-check disableHooks" >&2; exit 1; }

        # Overwrite rather than delete: an empty hook set is unambiguous to the
        # plugin loader and keeps the file present so the guard above stays
        # meaningful. The hook scripts are left in place (unreferenced, harmless)
        # so flipping the option back needs no other change.
        echo '{"hooks":{}}' > "$out/hooks/hooks.json"
      '' else ''
        # hooks.json invokes its own hook runner via
        # "''${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd", and CLAUDE_PLUGIN_ROOT is
        # NOT set for SessionStart events -- the hook fails silently, which is the
        # failure mode hardest to notice, since a missing session preamble looks
        # like a model that just didn't reach for a skill. Baking the real store
        # path is the fix.
        #
        # The hook script itself needs no patching: it derives the plugin root
        # from its own $0, so once hooks.json points at the right run-hook.cmd
        # everything below resolves relative to it.
        grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json" \
          || { echo "hooks.json no longer references CLAUDE_PLUGIN_ROOT; re-check this build" >&2; exit 1; }

        substituteInPlace "$out/hooks/hooks.json" \
          --replace-fail '${pluginRootVar}' '${builtins.placeholder "out"}'

        # `if`, not `grep && exit` -- a correct run leaves no match, so grep exits
        # 1 and the && form would fail precisely when it succeeded.
        if grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json"; then
          echo "substitution left a CLAUDE_PLUGIN_ROOT reference behind" >&2
          exit 1
        fi
      ''
    }

    # The hook runner and its scripts must stay executable through the copy,
    # whether or not anything currently invokes them.
    chmod +x "$out/hooks/run-hook.cmd" "$out/hooks/session-start"

    ${lib.optionalString disableSpecCommits ''
      # The replacement wording deliberately says "add it to git" rather than
      # "do not commit it": the tripwire below counts lines matching 'commit', so
      # prose containing the word would inflate the count and blunt it.
      substituteInPlace "$out/skills/brainstorming/SKILL.md" \
        --replace-fail \
          '6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and commit' \
          '6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. Do NOT add it to git.' \
        --replace-fail \
          '- Commit the design document to git' \
          '- Do NOT add the design document to git. The spec is a working note, not repo history.' \
        --replace-fail \
          '> "Spec written and committed to `<path>`.' \
          '> "Spec written to `<path>`.'

      # The two survivors in brainstorming are both "check ... recent commits"
      # (reading history, not writing it); all four in writing-plans are about
      # committing the implementation, which this option deliberately keeps.
      for check in brainstorming:2 writing-plans:4; do
        skill="''${check%:*}"
        want="''${check#*:}"
        got=$(grep -ci 'commit' "$out/skills/$skill/SKILL.md" || true)
        [ "$got" = "$want" ] || {
          echo "$skill/SKILL.md: expected $want lines mentioning 'commit', found $got." >&2
          echo "Upstream changed its commit guidance -- re-read the diff before bumping this count." >&2
          exit 1
        }
      done
    ''}
  ''
