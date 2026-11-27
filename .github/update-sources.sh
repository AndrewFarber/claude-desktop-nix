#!/usr/bin/env bash
# Rewrite sources.json from Anthropic's signed apt repo.
# Trust chain: pinned key -> InRelease signature -> Packages sha256 -> .deb sha256.
# Needs: curl, gpg, jq, sha256sum. Run from the repo root.
set -euo pipefail

base=https://downloads.claude.ai/claude-desktop/apt/stable
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

gpg --quiet --dearmor --output "$work/key.gpg" keys/claude-desktop.asc
curl -fsSL "$base/dists/stable/InRelease" -o "$work/InRelease"
gpgv --quiet --keyring "$work/key.gpg" --output "$work/Release" "$work/InRelease"

entry() { # nix-system deb-arch
  local index=main/binary-$2/Packages expected
  expected=$(awk -v f="$index" '/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1 }' "$work/Release")
  [[ -n "$expected" ]] || { echo "no $index in Release" >&2; exit 1; }

  curl -fsSL "$base/dists/stable/$index" -o "$work/Packages-$2"
  echo "$expected  $work/Packages-$2" | sha256sum --check --quiet

  awk '/^Version: / { v = $2 } /^Filename: / { f = $2 } /^SHA256: / { print v, f, $2 }' "$work/Packages-$2" |
    sort -V | tail -1 |
    jq -R --arg sys "$1" --arg base "$base" \
      'split(" ") | {($sys): {version: .[0], url: "\($base)/\(.[1])", sha256: .[2]}}'
}

{
  entry x86_64-linux amd64
  entry aarch64-linux arm64
} | jq -s 'add' >sources.json
