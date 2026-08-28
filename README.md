# harness-config.nix

Reusable Claude Code / agent tooling for [home-manager][hm], packaged as a Nix
flake. It provides package transformations and plugins for existing agents, a
Lavish AXI build function, and a home-manager module for it.

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
- **`lib.wrapOpencode`** — the same `package -> package` shape for opencode,
  setting its Claude Code compatibility gates. opencode silently falls back to
  Claude's prompt files and `~/.claude/skills` when no opencode-native file is
  present; on a host that runs both agents deliberately that is a leak, and
  these are the environment variables that switch it off. `home.sessionVariables`
  would disable the fallback for *every* process, so the scoping needs a wrapper.
  Serves opencode v1 and the v2 beta (`opencode2`) via `binName`.
- **`lib.mkSuperpowersPlugin`** — builds [obra/superpowers][sp] into a
  force-loadable Claude Code plugin, with optional customizations applied on top
  of upstream's source.
- **`lib.mkLavishAxi`** — builds a pinned Lavish AXI release on the consumer's
  own `pkgs`, with opt-in reverse-proxy support (`enableProxySupport = true`)
  and the agent skill packaged for declarative registration.
- **`homeManagerModules.lavish`** — installs and configures Lavish AXI, can
  opt out of telemetry via a `programs.lavish.disableTelemetry` flag, and can
  register the packaged skill with Claude Code, OpenCode, or both.
  `homeManagerModules.default` is an alias for the same module.

The `lib` helpers are pure functions that take the consumer's own `pkgs` as an
argument. This flake ships no packages itself: `claude-code` and opencode come
from the consumer's channel, and `mkLavishAxi` builds lavish on demand with the
consumer's `pkgs`. So `allowUnfree` and the nixpkgs channel stay entirely the
consumer's; the consumer applies these functions in their own home-manager
config.

[hm]: https://github.com/nix-community/home-manager
[sp]: https://github.com/obra/superpowers
[lavish]: https://github.com/kunchenguid/lavish-axi

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

### `lib.wrapOpencode`

Returns an opencode package with a thin `writeShellScriptBin` wrapper that sets
opencode's [Claude Code compatibility][occ] gates before `exec`-ing the real
binary. If no toggle is requested, it returns the input `package`
**unchanged** — no wrapper enters the `PATH`.

opencode, with no opencode-native file present, falls back to reading the
project `CLAUDE.md` (when there is no `AGENTS.md`), `~/.claude/CLAUDE.md` (when
there is no `~/.config/opencode/AGENTS.md`), and `~/.claude/skills`
unconditionally. Each half of that fallback is gated by an environment variable.

| Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `pkgs` | package set (nixpkgs instance) | **required** | The consumer's `pkgs`. Used for `lib` and `writeShellScriptBin`; keeps `allowUnfree` and the channel the consumer's. |
| `package` | package (a derivation) | **required** | The opencode package to wrap (the consumer's `pkgs.opencode` for v1, or a self-built `opencode2` for the v2 beta). |
| `binName` | str | `"opencode"` | The binary to expose. `"opencode"` for v1, `"opencode2"` for the v2 beta, so a host can wrap and install both side by side. |
| `disableClaudeCompat` | bool | `false` | Disable Claude Code compatibility wholesale (`OPENCODE_DISABLE_CLAUDE_CODE=1`): neither Claude's prompt files nor skills are read. Subsumes the two toggles below. |
| `disableClaudePrompt` | bool | `false` | Disable only the Claude prompt fallback (`OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`) — `CLAUDE.md` project and global files; skills are still read. A v1 concern (v2 discovers `AGENTS.md` only), inert but harmless on v2. |
| `disableClaudeSkills` | bool | `false` | Disable only the `~/.claude/skills` fallback (`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`); Claude's prompt files are still read. Applies to both v1 and v2. |

**Returns:** the input `package` untouched when every toggle is off; otherwise a
`writeShellScriptBin binName` wrapper that sets the requested variables and
`exec`s `${package}/bin/${binName} "$@"`.

Each exported variable uses `:-` default semantics, so a value present in the
session's environment wins — e.g. `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=0` remains
a per-session escape hatch.

```nix
# Run opencode without reading Claude's global prompt or skills:
programs.opencode.package = harnessConfig.lib.wrapOpencode {
  inherit pkgs;
  package = pkgs.opencode;
  disableClaudePrompt = true;
  disableClaudeSkills = true;
};
```

[occ]: https://opencode.ai/docs/rules/#claude-code-compatibility

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

### `lib.mkLavishAxi`

Builds a Lavish AXI release from a source pin and a fixed pnpm dependency
closure, on the consumer's own `pkgs`. The output exposes the `lavish-axi`
executable and installs the upstream skill at
`share/lavish-axi/skill/SKILL.md`.

| Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `pkgs` | package set (nixpkgs instance) | **required** | The consumer's `pkgs`. |
| `src` | path / source | the flake's pinned `lavish-axi` input (`lavish-axi-v0.1.43`) | Upstream's source tree. Override to pin your own revision; pass a matching `version`. |
| `version` | str | `"0.1.43"` | The release being built. Override to match a new pin. |
| `enableProxySupport` | bool | `false` | Enable Express proxy trust so forwarded request metadata works behind a reverse proxy, and recognize `LAVISH_AXI_LINK_SCHEME` / `LAVISH_AXI_LINK_PORT` in generated links — an HTTPS public URL with a different or omitted public port while the service listens locally over HTTP. |

**Returns:** the packaged `lavish-axi` derivation. The packaged skill always
invokes that executable directly rather than through `npx`, so using the skill
does not download or run a different Lavish release at runtime.

```nix
programs.lavish.package = harnessConfig.lib.mkLavishAxi {
  inherit pkgs;
  enableProxySupport = true;
};
```

### `homeManagerModules.lavish`

The module is also exported as `homeManagerModules.default`. Import either name,
then enable and configure `programs.lavish`:

```nix
{
  imports = [ inputs.harness-config.homeManagerModules.lavish ];
  programs.lavish = {
    enable = true;
    disableTelemetry = true;
    host = "127.0.0.1";
    linkHost = "lavish.example.org";
    linkScheme = "https";
    linkPort = "";
    allowedHosts = [ "lavish.example.org" ];
    port = 4385;
  };
}
```

The `package` option defaults to this flake's pinned release built with
`enableProxySupport = true`; override it to use another Lavish build. Skill
registration expects the package to provide `share/lavish-axi/skill/SKILL.md`.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `programs.lavish.enable` | bool | `false` | Install and configure Lavish AXI. When disabled, the module adds no package, variables, or skills. |
| `programs.lavish.package` | package | `harnessConfig.lib.mkLavishAxi { inherit pkgs; enableProxySupport = true; }` — this flake's pinned release with proxy support | Package to install. Override this to use another Lavish build. |
| `programs.lavish.disableTelemetry` | bool | `false` | Set `LAVISH_AXI_TELEMETRY=0` in `home.sessionVariables`, opting out of Lavish's telemetry. |
| `programs.lavish.host` | null or string | `null` | Set `LAVISH_AXI_HOST`, typically to the local listening address. |
| `programs.lavish.linkHost` | null or string | `null` | Set `LAVISH_AXI_LINK_HOST`, the host used in generated public links. |
| `programs.lavish.linkScheme` | `"http"`, `"https"`, or null | `null` | Set `LAVISH_AXI_LINK_SCHEME` for generated links. |
| `programs.lavish.linkPort` | string or null | `null` | Set `LAVISH_AXI_LINK_PORT` for generated links. Use `""` to omit the port entirely. |
| `programs.lavish.allowedHosts` | list of strings | `[ ]` | Set `LAVISH_AXI_ALLOWED_HOSTS`. Multiple hosts are joined into one space-separated value. |
| `programs.lavish.port` | port or null | `null` | Set `LAVISH_AXI_PORT`, converted to a string in the session environment. |
| `programs.lavish.claudeCodeSkill.enable` | bool | `false` | Register the packaged `lavish` skill in `programs.claude-code.skills`. |
| `programs.lavish.opencodeSkill.enable` | bool | `false` | Register the packaged `lavish` skill in `programs.opencode.skills`. |

## Flake outputs

- **`lib`** — the four system-independent functions above: `wrapClaudeCode`,
  `wrapOpencode`, `mkSuperpowersPlugin`, and `mkLavishAxi`. They take the
  consumer's `pkgs` as an argument, so they live under `lib` rather than a
  `packages.${system}` output.
- **`homeManagerModules.lavish`** — the `programs.lavish` module described above.
- **`homeManagerModules.default`** — an alias for `homeManagerModules.lavish`.
- **`checks.${system}`** — flake-check tests for the four `lib` helpers, the
  Lavish package build (defaults and the proxy knob) and the module's defaults,
  telemetry option, environment, package override, and independent skill
  registration.

There is no `packages.${system}` output. Lavish ships through `lib.mkLavishAxi`;
claude-code and opencode come from the consumer's own channel.

Supported platforms: `aarch64-darwin`, `aarch64-linux`, `x86_64-linux`.

Inputs: `nixpkgs` tracks `nixos-26.05`; `home-manager` tracks `release-26.05`;
`superpowers` is pinned to a release tag (`obra/superpowers` `v6.2.0`) and
consumed as a source (`flake = false`), because it ships a `SessionStart` hook
that injects context into every session — an unpinned bump would change every
consumer's prompt with no lock diff to show for it; `lavish-axi` is likewise
pinned to a release tag (`lavish-axi-v0.1.43`) and consumed as a source.