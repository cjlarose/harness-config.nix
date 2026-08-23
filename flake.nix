{
  description =
    "Reusable Claude Code / agent tooling for home-manager (cjlarose harness config)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      supportedPlatforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllPlatforms = nixpkgs.lib.genAttrs supportedPlatforms;
    in
    {
      # The Claude Code environment wrapper. System-independent: it takes the
      # consumer's pkgs as an argument, so it lives here rather than under
      # packages.${system}. See lib/wrap-claude-code.nix.
      lib.wrapClaudeCode = import ./lib/wrap-claude-code.nix;

      # Scaffold for later tasks. Empty in this PR: claude-code/opencode come
      # from the consumer's pkgs, and no self-built tool exists yet.
      packages = forAllPlatforms (system: { });

      checks = forAllPlatforms (system:
        import ./tests/wrap-claude-code.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (self.lib) wrapClaudeCode;
        });
    };
}
