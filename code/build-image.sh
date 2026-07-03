#!/usr/bin/env bash
set -euo pipefail

# Build the Nix-generated container image and load it into local Podman.
# Runtime orchestration is intentionally kept out of the flake; this script only
# builds/loads the prebuilt tag consumed by run-image.sh.
#
# Usage:
#   ./build-image.sh [--update] [--outfitter-version VERSION]
#
# Resulting image tag:
#   localhost/nix-zellij-agent:dev
#
# --update refreshes flake inputs, bumps @ai-outfitter/outfitter to the latest
# npm-published version or the version passed with --outfitter-version, updates
# the fixed-output npm hash, then rebuilds and reloads the local image tag.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FLAKE_REF="path:$SCRIPT_DIR"
IMAGE_REF="localhost/nix-zellij-agent:dev"
NIX_FLAGS=(
  --accept-flake-config
  --extra-experimental-features "nix-command flakes"
)
UPDATE=0
OUTFITTER_VERSION=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--update] [--outfitter-version VERSION]

Build and load $IMAGE_REF.

Options:
  --update                    Update flake inputs, bump @ai-outfitter/outfitter, refresh the npm hash, then build.
  --outfitter-version VERSION Pin @ai-outfitter/outfitter to VERSION during --update instead of latest.
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE=1
      shift
      ;;
    --outfitter-version)
      if [[ -z "${2:-}" ]]; then
        echo "error: --outfitter-version requires a version" >&2
        exit 1
      fi
      OUTFITTER_VERSION="$2"
      shift 2
      ;;
    --outfitter-version=*)
      OUTFITTER_VERSION="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

npm_view_version() {
  local package="$1"
  if command -v npm >/dev/null 2>&1; then
    npm view "$package" version
  else
    nix shell "${NIX_FLAGS[@]}" nixpkgs#nodejs_22 --command npm view "$package" version
  fi
}

update_outfitter_pin() {
  local current_version target_version hash_log new_hash

  current_version="$(grep -Eo '@ai-outfitter/outfitter@[0-9][^[:space:]\\]*' "$SCRIPT_DIR/flake.nix" | head -n1 | sed 's/^@ai-outfitter\/outfitter@//')"
  if [[ -z "$current_version" ]]; then
    echo "error: could not find @ai-outfitter/outfitter pin in $SCRIPT_DIR/flake.nix" >&2
    exit 1
  fi

  target_version="${OUTFITTER_VERSION:-$(npm_view_version '@ai-outfitter/outfitter')}"
  if [[ -z "$target_version" ]]; then
    echo "error: could not resolve target @ai-outfitter/outfitter version" >&2
    exit 1
  fi

  echo "updating flake inputs" >&2
  nix flake update "${NIX_FLAGS[@]}" --flake "$SCRIPT_DIR"

  echo "pinning @ai-outfitter/outfitter $current_version -> $target_version" >&2
  sed -i -E \
    -e "s|@ai-outfitter/outfitter@[0-9][^[:space:]\\]*|@ai-outfitter/outfitter@$target_version|" \
    -e 's|outputHash = "sha256-[^"]+";|outputHash = lib.fakeHash;|' \
    "$SCRIPT_DIR/flake.nix"

  hash_log="$(mktemp -t zejent-npm-hash.XXXXXX.log)"
  set +e
  nix build "${NIX_FLAGS[@]}" --no-link "$FLAKE_REF#node-tools" >"$hash_log" 2>&1
  local build_status=$?
  set -e

  new_hash="$(grep -Eo 'got:[[:space:]]+sha256-[A-Za-z0-9+/=]+' "$hash_log" | tail -n1 | awk '{print $2}')"
  if [[ -z "$new_hash" ]]; then
    cat "$hash_log" >&2
    rm -f "$hash_log"
    if [[ "$build_status" == "0" ]]; then
      echo "error: node-tools build unexpectedly succeeded with lib.fakeHash; refusing to leave flake.nix with a fake hash" >&2
    else
      echo "error: could not discover new npm fixed-output hash" >&2
    fi
    exit 1
  fi
  rm -f "$hash_log"

  echo "pinning npm fixed-output hash: $new_hash" >&2
  sed -i -E "s|outputHash = lib.fakeHash;|outputHash = \"$new_hash\";|" "$SCRIPT_DIR/flake.nix"
}

if [[ "$UPDATE" == "1" ]]; then
  update_outfitter_pin
fi

nix build "${NIX_FLAGS[@]}" --out-link "$SCRIPT_DIR/result" "$FLAKE_REF#image"
podman load -i "$SCRIPT_DIR/result"
podman image exists "$IMAGE_REF"
echo "loaded $IMAGE_REF"
