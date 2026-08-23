{
  description =
    "Reusable Claude Code / agent tooling for home-manager (cjlarose harness config)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # obra/superpowers, pinned to a release tag rather than a branch: it ships a
    # SessionStart hook that injects context into every session, so an unpinned
    # bump would change every consumer's prompt with no lock diff to show for it.
    # Consumed as a source (flake = false); lib.mkSuperpowersPlugin builds it.
    superpowers = {
      url = "github:obra/superpowers/v6.2.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, superpowers }:
    let
      supportedPlatforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllPlatforms = nixpkgs.lib.genAttrs supportedPlatforms;
    in
    {
      lib = {
        # The Claude Code environment wrapper. System-independent: it takes the
        # consumer's pkgs as an argument, so it lives here rather than under
        # packages.${system}. See lib/wrap-claude-code.nix.
        wrapClaudeCode = import ./lib/wrap-claude-code.nix;

        # Builds obra/superpowers into a Claude Code plugin. Closes over the
        # pinned superpowers source; the consumer passes pkgs and may override
        # the customizations (and src). See lib/superpowers.nix.
        mkSuperpowersPlugin = args:
          import ./lib/superpowers.nix ({ src = superpowers; } // args);
      };

      # Scaffold for later tasks. Empty for now: claude-code/opencode come from
      # the consumer's pkgs, and no self-built tool package exists yet.
      packages = forAllPlatforms (system: { });

      checks = forAllPlatforms (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests/wrap-claude-code.nix {
          inherit pkgs;
          inherit (self.lib) wrapClaudeCode;
        }
        // import ./tests/superpowers.nix {
          inherit pkgs;
          inherit (self.lib) mkSuperpowersPlugin;
        });
    };
}
