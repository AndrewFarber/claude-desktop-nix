#!/usr/bin/env bash
# Rewrite sources.json from Anthropic's signed apt repo.
# Trust chain: pinned key -> InRelease signature -> Packages sha256 -> .deb sha256.
# Also refuses expired metadata (replayed InRelease), version downgrades, and
# architectures that disagree on the version.
# Needs: curl, gpg, gpgv, jq, sha256sum, GNU date. Run from the repo root.
set -euo pipefail

base=https://downloads.claude.ai/claude-desktop/apt/stable
package=claude-desktop
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

die() {
  echo "update-sources: $*" >&2
  exit 1
}

gpg --quiet --dearmor --output "$work/key.gpg" keys/claude-desktop.asc
curl -fsSL --proto '=https' "$base/dists/stable/InRelease" -o "$work/InRelease"
gpgv --quiet --keyring "$work/key.gpg" --output "$work/Release" "$work/InRelease"

# gpgv only checks the signature. A replayed old InRelease still verifies, so
# enforce Valid-Until as apt does.
valid_until=$(sed -n 's/^Valid-Until: //p' "$work/Release")
[[ -n "$valid_until" ]] || die "Release has no Valid-Until field"
(($(date -d "$valid_until" +%s) > $(date +%s))) || die "Release expired at $valid_until"

entry() { # nix-system deb-arch
  local index=main/binary-$2/Packages expected latest version filename sha256 current newest
  expected=$(awk -v f="$index" '/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1 }' "$work/Release")
  [[ -n "$expected" ]] || die "no $index in Release"

  curl -fsSL --proto '=https' "$base/dists/stable/$index" -o "$work/Packages-$2"
  echo "$expected  $work/Packages-$2" | sha256sum --check --quiet

  # Parse per stanza so fields never leak between entries, and keep only our
  # package in case the repo starts carrying others.
  latest=$(awk -v pkg="$package" '
    function flush() {
      if (p == pkg && v != "" && f != "" && h != "") print v, f, h
      p = v = f = h = ""
    }
    /^$/ { flush(); next }
    /^Package: / { p = $2 }
    /^Version: / { v = $2 }
    /^Filename: / { f = $2 }
    /^SHA256: / { h = $2 }
    END { flush() }
  ' "$work/Packages-$2" | sort -V | tail -1)
  [[ -n "$latest" ]] || die "no $package in $index"
  read -r version filename sha256 <<<"$latest"

  current=$(jq -r --arg sys "$1" '.[$sys].version // empty' sources.json 2>/dev/null || true)
  if [[ -n "$current" ]]; then
    newest=$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)
    [[ "$newest" == "$version" ]] || die "refusing downgrade on $1: $current -> $version"
  fi

  jq -n --arg sys "$1" --arg version "$version" --arg url "$base/$filename" --arg sha256 "$sha256" \
    '{($sys): {$version, $url, $sha256}}'
}

# Build into the work dir: entry() reads the current sources.json, and a
# failure must leave it untouched.
{
  entry x86_64-linux amd64
  entry aarch64-linux arm64
} | jq -s 'add' >"$work/sources.json"

[[ $(jq '[.[].version] | unique | length' "$work/sources.json") == 1 ]] ||
  die "architectures disagree on the version: $(jq -c 'map_values(.version)' "$work/sources.json")"

mv "$work/sources.json" sources.json
