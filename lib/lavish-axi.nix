# Lavish AXI as a pure function, in the style of wrapClaudeCode: call it from a
# consumer's home-manager config with that consumer's own pkgs, so the nixpkgs
# channel and platform stay entirely theirs.
#
# Usage (in a home-manager config):
#
#   programs.lavish.package = harnessConfig.lib.mkLavishAxi {
#     inherit pkgs;
#     enableProxySupport = true;
#   };
#
# src and version default to harness-config's own pinned input (see flake.nix);
# a consumer may override either to pin their own release.
{ pkgs
, # Upstream's lavish-axi source tree.
  src
, # The release version being built, matched to src.
  version
, # Apply the reverse-proxy patches: trust proxy in the Express server, plus
  # LAVISH_AXI_LINK_SCHEME / LAVISH_AXI_LINK_PORT public-link rewriting. Off by
  # default; enable when the service runs behind a reverse proxy.
  enableProxySupport ? false
,
}:
pkgs.callPackage ./../packages/lavish-axi {
  inherit src version enableProxySupport;
}
