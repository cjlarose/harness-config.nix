{ lib
, stdenv
, nodejs_26
, pnpm
, pnpmConfigHook
, fetchPnpmDeps
, makeWrapper
, src
, version
, # Apply the reverse-proxy patches (trust proxy, LAVISH_AXI_LINK_* rewriting).
  enableProxySupport ? false
,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lavish-axi";
  inherit version src;

  # A fixed dependency closure keeps the package reproducible with the source pin.
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 3;
    hash = "sha256-y4KeFqPF02TBSlP1mgyj5UFx0Q98ip890xYkBAYF4qY=";
  };

  nativeBuildInputs = [
    nodejs_26
    pnpm
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    pnpm run build

    ${lib.optionalString enableProxySupport ''
      # Honor forwarded request metadata when the server runs behind a proxy.
      substituteInPlace dist/cli.mjs \
        --replace-fail 'const app = express()' \
                       'const app = express(); app.set("trust proxy", "loopback")'
      substituteInPlace dist/cli.mjs \
        --replace-fail '`http://''${hostForUrl(linkHostName)}:''${publicPort}/session/''${key}`' \
                       '(() => { const s = process.env.LAVISH_AXI_LINK_SCHEME || "http"; const lp = process.env.LAVISH_AXI_LINK_PORT; const pp = lp === undefined ? `:''${publicPort}` : (lp === "" ? "" : `:''${lp}`); return `''${s}://''${hostForUrl(linkHostName)}''${pp}/session/''${key}`; })()'
    ''}

    # Keep only runtime dependencies in the installed package.
    pnpm prune --prod --ignore-scripts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/lavish-axi" "$out/bin" "$out/share/lavish-axi/skill"
    cp -r dist node_modules package.json "$out/lib/lavish-axi/"
    install -Dm644 skills/lavish/SKILL.md "$out/share/lavish-axi/skill/SKILL.md"

    # Invoke the packaged executable directly instead of downloading it with npx.
    substituteInPlace "$out/share/lavish-axi/skill/SKILL.md" \
      --replace-fail 'npx -y lavish-axi' 'lavish-axi'

    makeWrapper ${nodejs_26}/bin/node $out/bin/lavish-axi \
      --add-flags $out/lib/lavish-axi/dist/cli.mjs

    runHook postInstall
  '';

  meta = {
    description = "Reviewable HTML artifacts for coding agents";
    homepage = "https://github.com/kunchenguid/lavish-axi";
    license = lib.licenses.mit;
    mainProgram = "lavish-axi";
    platforms = lib.platforms.unix;
  };
})
