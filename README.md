# harness-config.nix

Reusable Claude Code / agent tooling for [home-manager][hm], packaged as a Nix
flake.

Claude Code itself is left entirely to the stock `programs.claude-code`
home-manager module: it already covers the package, settings, MCP servers,
plugins, hooks and LSP servers. This flake fills the gaps that module does not,
and only those:

- **`lib.wrapClaudeCode`** — a `package -> package` transformation that sets the
  environment `claude` wants at launch. Only one tweak genuinely needs a
  wrapper: unsetting `$TMUX` for `claude` alone. `$TMUX` has to stay set for
  every other program in the terminal, so the unset must be scoped to the
  `claude` process — and `home.sessionVariables` can only *set* a variable, not
  scope-unset one. The remaining variables are claude-only (nothing else reads
  them), so they would be harmless as session variables; the wrapper keeps them
  anyway, so all of claude's environment stays scoped to `claude` and lives in
  one place.
- **`lib.mkSuperpowersPlugin`** — builds [obra/superpowers][sp] into a
  force-loadable Claude Code plugin, with optional customizations applied on top
  of upstream's source.

Both are exposed as pure `lib` functions that take the consumer's own `pkgs` as
an argument. This flake never builds `claude-code` (or opencode) itself, so
`allowUnfree` and the nixpkgs channel stay entirely the consumer's; the consumer
applies these functions in their own home-manager config.

[hm]: https://github.com/nix-community/home-manager
[sp]: https://github.com/obra/superpowers

## Getting started

Add the flake as an input:

```nix
{
  inputs.harness-config.url = "github:cjlarose/harness-config.nix";
}
```

Then apply the two idioms in a home-manager config (with the flake passed in as,
say, `harnessConfig`):

```nix
{ pkgs, harnessConfig, ... }:
{
  # 1. Wrap the claude-code package with the environment tweaks you want.
  programs.claude-code.package = harnessConfig.lib.wrapClaudeCode {
    inherit pkgs;
    package = pkgs.claude-code;
    trueColorInTmux = true;
    fullscreenTui = true;
    toolShell = "${pkgs.bashInteractive}/bin/bash";
    agentTeams = true;
  };

  # 2. Add the superpowers plugin (home-manager >= 26.05, where
  #    programs.claude-code.plugins exists).
  programs.claude-code.plugins = [
    (harnessConfig.lib.mkSuperpowersPlugin {
      inherit pkgs;
      disableHooks = true;
      disableSpecCommits = true;
    })
  ];
}
```

home-manager wraps the resulting package again with its own `--plugin-dir`
flags, so the final runtime chain is: HM plugin wrapper -> this env wrapper ->
`claude-code`.

## API

### `lib.wrapClaudeCode`

Returns a `claude-code` package with a thin `writeShellScriptBin` wrapper that
sets the requested environment before `exec`-ing the real binary. If no toggle
is requested, it returns the input `package` **unchanged** — no wrapper enters
the `PATH`.

| Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `pkgs` | package set (nixpkgs instance) | **required** | The consumer's `pkgs`. Used for `lib` and `writeShellScriptBin`; keeps `allowUnfree` and the channel the consumer's. |
| `package` | package (a derivation) | **required** | The unwrapped `claude-code` package to patch on top of (e.g. `pkgs.claude-code`, or a pinned node build on a no-AVX host). |
| `trueColorInTmux` | bool | `false` | Unset `$TMUX` for `claude` only, so it renders in 24-bit color instead of being capped at 256 inside a tmux session. |
| `fullscreenTui` | bool | `false` | Opt into the fullscreen (alt-screen, flicker-free) TUI renderer by exporting `CLAUDE_CODE_NO_FLICKER=1`. |
| `toolShell` | str (absolute path) or `null` | `null` | Absolute path to the shell `claude` runs its Bash tool under (exported as `CLAUDE_CODE_SHELL`), or `null` to leave it following `$SHELL`. |
| `agentTeams` | bool | `false` | Enable the experimental subagent-teams capability by exporting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. |

**Returns:** the input `package` untouched when every toggle is off/`null`;
otherwise a `writeShellScriptBin "claude"` wrapper that sets the environment and
`exec`s `${package}/bin/claude "$@"`.

Each exported variable uses `:-` default semantics, so a value present in the
session's environment wins over the wrapper's — e.g. `CLAUDE_CODE_NO_FLICKER=0`,
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0`, or an explicit `CLAUDE_CODE_SHELL`
remain per-session escape hatches. (`trueColorInTmux` is the exception: it
`unset`s `$TMUX` outright, only within the `claude` process.)

```nix
programs.claude-code.package = harnessConfig.lib.wrapClaudeCode {
  inherit pkgs;
  package = pkgs.claude-code;
  trueColorInTmux = true;
  fullscreenTui = true;
  toolShell = "${pkgs.bashInteractive}/bin/bash";
  agentTeams = true;
};
```

### `lib.mkSuperpowersPlugin`

Builds [obra/superpowers][sp] into a Claude Code plugin. Upstream already ships
the plugin layout (`.claude-plugin/plugin.json`, `skills/`, `hooks/`), so this
is a copy-with-edits rather than a compile; the customizations are driven by
arguments so a consumer opts into them.

| Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `pkgs` | package set (nixpkgs instance) | **required** | The consumer's `pkgs`. Used for `lib` and `runCommand`. |
| `src` | path / source | the flake's pinned `obra/superpowers` input (currently `v6.2.0`) | Upstream's superpowers source tree. Override to pin your own revision. |
| `disableHooks` | bool | `false` | Ship the plugin with an empty hook set, replacing upstream's `hooks/hooks.json`. Upstream registers a `SessionStart` hook that injects `using-superpowers` into every session; this switches that off. |
| `disableSpecCommits` | bool | `false` | Patch the brainstorming skill so it does not instruct committing the design doc to git. |

**Returns:** a Claude Code plugin derivation (`superpowers-plugin`, built with
`runCommand`). Its `/skills` subdir also serves opencode directly.

Behavior of each customization:

- **`disableHooks`** — when `true`, `hooks/hooks.json` is overwritten with
  `{"hooks":{}}` (rather than deleted, so the loader sees an unambiguous empty
  set and flipping the option back needs no other change; the hook scripts are
  left in place, unreferenced and harmless). When `false`, the build instead
  bakes the real store path into `hooks.json` in place of `${CLAUDE_PLUGIN_ROOT}`
  — that variable is not set for `SessionStart` events, so without this the hook
  would fail silently.
- **`disableSpecCommits`** — rewrites the three lines in
  `skills/brainstorming/SKILL.md` that tell the model to commit the design
  document, turning them into "do not add it to git" wording. Commit guidance
  elsewhere (e.g. `writing-plans`, which is about committing the implementation)
  is deliberately kept.

Every edit is a `--replace-fail` or an explicit guard, so an upstream rewording
breaks the build rather than silently shipping unmodified text.

```nix
# home-manager >= 26.05 (programs.claude-code.plugins):
programs.claude-code.plugins = [
  (harnessConfig.lib.mkSuperpowersPlugin {
    inherit pkgs;
    disableHooks = true;
    disableSpecCommits = true;
  })
];

# The same build serves opencode via its /skills subdir:
programs.opencode.settings.skills.paths =
  [ "${harnessConfig.lib.mkSuperpowersPlugin { inherit pkgs; }}/skills" ];
```

## Flake outputs

- **`lib`** — the two system-independent functions above: `wrapClaudeCode` and
  `mkSuperpowersPlugin`. They take the consumer's `pkgs` as an argument, so they
  live under `lib` rather than `packages.${system}`.
- **`packages.${system}`** — a scaffold for later tasks. **Currently empty**:
  `claude-code`/opencode come from the consumer's `pkgs`, and no self-built tool
  package exists yet.
- **`checks.${system}`** — the flake-check tests for the two `lib` functions
  (from `tests/wrap-claude-code.nix` and `tests/superpowers.nix`), covering the
  identity/selective/full wrapper behavior and the superpowers structure, baked
  hooks, `disableHooks`, and `disableSpecCommits` customizations.

Supported platforms: `aarch64-darwin`, `aarch64-linux`, `x86_64-linux`.

Inputs: `nixpkgs` tracks `nixos-26.05`; `superpowers` is pinned to a release tag
(`obra/superpowers` `v6.2.0`) and consumed as a source (`flake = false`), because
it ships a `SessionStart` hook that injects context into every session — an
unpinned bump would change every consumer's prompt with no lock diff to show for
it.
