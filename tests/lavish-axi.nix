{ pkgs, mkLavishAxi }:
{
  # The default build keeps upstream behavior. A knob defaulting on is caught
  # by the explicit guards -- a bare `! grep` cannot, because `!` lists are
  # exempt from set -e, so a silent pass would be invisible.
  lavish-axi-defaults = pkgs.runCommand "lavish-axi-defaults"
    { package = mkLavishAxi { inherit pkgs; }; } ''
    set -e
    test -x "$package/bin/lavish-axi"
    test -f "$package/share/lavish-axi/skill/SKILL.md"
    if grep -Fq 'npx -y lavish-axi' "$package/share/lavish-axi/skill/SKILL.md"; then
      echo "defaults skill still fetches via npx" >&2
      exit 1
    fi
    grep -Fq 'lavish-axi' "$package/share/lavish-axi/skill/SKILL.md"
    if grep -Fq 'trust proxy' "$package/lib/lavish-axi/dist/cli.mjs"; then
      echo "defaults build unexpectedly enables trust proxy" >&2
      exit 1
    fi
    touch "$out"
  '';

  lavish-axi-proxy-http =
    pkgs.runCommand "lavish-axi-proxy-http"
      {
        nativeBuildInputs = [ pkgs.curl pkgs.jq pkgs.python3 ];
        package = mkLavishAxi {
          inherit pkgs;
          enableProxySupport = true;
        };
      }
      ''
              set -euo pipefail
              state_dir="$TMPDIR/lavish-state"
              artifact="$TMPDIR/artifact.html"
              public_host="proxy.example"
              public_port=8443
              port="$(python3 - <<'PY'
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            print(sock.getsockname()[1])
        PY
        )"
              server_pid=""

              cleanup() {
                if [ -n "$server_pid" ]; then
                  kill "$server_pid" 2>/dev/null || true
                  wait "$server_pid" 2>/dev/null || true
                fi
              }
              trap cleanup EXIT

              mkdir -p "$state_dir"
              printf '%s\n' '<!doctype html><html><body>proxy test</body></html>' > "$artifact"
              export LAVISH_AXI_HOST=127.0.0.1
              export LAVISH_AXI_LINK_HOST="$public_host"
              export LAVISH_AXI_LINK_SCHEME=https
              export LAVISH_AXI_LINK_PORT="$public_port"
              export LAVISH_AXI_STATE_DIR="$state_dir"
              export LAVISH_AXI_TELEMETRY=0
              "$package/bin/lavish-axi" server --port "$port" > "$state_dir/server.log" 2>&1 &
              server_pid=$!

              ready=""
              for _ in $(seq 1 50); do
                if curl --noproxy '*' --silent --fail --connect-timeout 1 --max-time 1 --header "Host: $public_host" \
                  "http://127.0.0.1:$port/health" > /dev/null 2>&1; then
                  ready=1
                  break
                fi
                sleep 0.1
              done
              if [ -z "$ready" ]; then
                cat "$state_dir/server.log" >&2
                exit 1
              fi

              session="$(curl --noproxy '*' --silent --show-error --fail --connect-timeout 1 --max-time 5 \
                --request POST \
                --header "Host: $public_host" \
                --header 'content-type: application/json' \
                --data "$(jq --null-input --arg file "$artifact" '{ file: $file }')" \
                "http://127.0.0.1:$port/api/sessions")"
              session_url="$(printf '%s' "$session" | jq --exit-status --raw-output '.url')"
              expected_prefix="https://$public_host:$public_port/session/"
              case "$session_url" in
                "$expected_prefix"*) ;;
                *)
                  printf 'expected session URL beginning %s, got %s\n' "$expected_prefix" "$session_url" >&2
                  exit 1
                  ;;
              esac
              share_status="$(curl --noproxy '*' --silent --connect-timeout 1 --max-time 5 --output "$TMPDIR/share.json" \
                --write-out '%{http_code}' \
                --request POST \
                --header "Host: $public_host" \
                --header "Origin: https://$public_host" \
                --header 'X-Forwarded-Proto: https' \
                --header 'content-type: application/json' \
                --data '{}' \
                "http://127.0.0.1:$port/api/not-a-session/share")"
              if [ "$share_status" != 404 ]; then
                printf 'expected proxy-aware same-origin request to return 404, got %s\n' "$share_status" >&2
                cat "$TMPDIR/share.json" >&2
                exit 1
              fi
              touch "$out"
      '';
}
