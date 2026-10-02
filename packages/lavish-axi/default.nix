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

let
  # The weak claim present verbatim in BOTH the workflow poll step and the
  # Commands & rules bullet of the upstream skill. --replace-fail rewrites every
  # occurrence and errors if it finds none, so one directive fixes both and a
  # reworded upstream fails the build instead of shipping the old advice.
  pollWeakClaim =
    "If the poll gets killed or times out anyway, just re-run it - queued feedback is never lost.";

  pollCorrectedClaim =
    "If the poll is killed or times out *while waiting*, just re-run it — feedback that is queued but not yet delivered survives that. It does NOT survive a kill or a line-dropping filter landing *during* delivery: the server empties the session `prompts` as it hands them over, so annotations already handed off are destroyed, and re-polling then blocks for the next batch instead of returning them. Never pipe `lavish-axi poll` through `tail`/`head`/`grep`/`sed`/`awk`; `tee` its full output to a durable per-iteration file and read every byte. If a batch is lost this way, believe the human and ask them to resend. See the \"Poll feedback safety\" section at the end of this skill.";
in
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

    # Harden the poll-feedback guidance. The upstream skill tells the agent a
    # killed `poll` can always be re-run because "queued feedback is never lost"
    # -- true only while it is WAITING. `poll` empties the session prompts as it
    # hands them over, so a line-dropping filter after it, or a kill landing
    # mid-delivery, destroys the user's annotations with no way to recover them.
    # Rewrite that claim wherever it appears and append the full safety section.
    # Like the npx rewrite above and lib/superpowers.nix, every edit is
    # --replace-fail plus a tripwire, so an upstream rewording fails the build
    # instead of silently shipping the old advice.
    substituteInPlace "$out/share/lavish-axi/skill/SKILL.md" \
      --replace-fail ${lib.escapeShellArg pollWeakClaim} ${lib.escapeShellArg pollCorrectedClaim}

    if grep -Fq 'queued feedback is never lost' "$out/share/lavish-axi/skill/SKILL.md"; then
      echo "the weak 'queued feedback is never lost' claim survived the rewrite" >&2
      exit 1
    fi

    printf '\n' >> "$out/share/lavish-axi/skill/SKILL.md"
    cat ${./poll-hardening.md} >> "$out/share/lavish-axi/skill/SKILL.md"

    grep -Fq 'Poll feedback safety' "$out/share/lavish-axi/skill/SKILL.md" \
      || { echo "poll-hardening section missing from skill" >&2; exit 1; }

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
