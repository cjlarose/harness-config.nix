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

    # lavish-axi, pinned to a release tag. Consumed as a source (flake = false);
    # lib.mkLavishAxi builds it.
    lavish-axi = {
      url = "github:kunchenguid/lavish-axi/lavish-axi-v0.1.43";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, superpowers, lavish-axi }:
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

        # The opencode environment wrapper. Same shape as wrapClaudeCode: takes
        # the consumer's pkgs and package, sets opencode's Claude Code
        # compatibility gates before exec. Serves opencode v1 and the v2 beta
        # via `binName`. See lib/wrap-opencode.nix.
        wrapOpencode = import ./lib/wrap-opencode.nix;

        # Builds obra/superpowers into a Claude Code plugin. Closes over the
        # pinned superpowers source; the consumer passes pkgs and may override
        # the customizations (and src). See lib/superpowers.nix.
        mkSuperpowersPlugin = args:
          import ./lib/superpowers.nix ({ src = superpowers; } // args);

        # Builds Lavish AXI as a derivation. Same shape as the other lib
        # helpers: takes the consumer's pkgs, so it builds with their platform
        # and channel. Closes over the pinned lavish-axi source and version; the
        # consumer may override src, version, and enableProxySupport. See
        # lib/lavish-axi.nix.
        mkLavishAxi = args:
          import ./lib/lavish-axi.nix
            ({ src = lavish-axi; version = "0.1.43"; } // args);
      };

      checks = forAllPlatforms (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests/wrap-claude-code.nix
          {
            inherit pkgs;
            inherit (self.lib) wrapClaudeCode;
          }
        // import ./tests/wrap-opencode.nix {
          inherit pkgs;
          inherit (self.lib) wrapOpencode;
        }
        // import ./tests/superpowers.nix {
          inherit pkgs;
          inherit (self.lib) mkSuperpowersPlugin;
        }
        // import ./tests/lavish-axi.nix {
          inherit pkgs;
          mkLavishAxi = self.lib.mkLavishAxi;
        });
    };
}
