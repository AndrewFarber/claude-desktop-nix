#!/usr/bin/env bash
# Rewrite sources.json from Anthropic's signed apt repo.
# Trust chain: pinned key -> InRelease signature -> Packages sha256 -> .deb sha256
# -> the Claude Code CLI pin (version + sha256) in the .deb's own manifest.
# Also refuses expired metadata (replayed InRelease), version downgrades, and
# architectures that disagree on the version.
# Needs: curl, gpg, gpgv, jq, sha256sum, dpkg-deb, tar, GNU date and grep.
# Run from the repo root.
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

cli_pin() { # deb-url deb-sha256 cli-platform
  # The app ships a manifest naming the exact Claude Code build it runs. It
  # sits uncompressed in app.asar, inside the .deb we just verified.
  local deb=$work/app.deb manifest
  curl -fsSL --proto '=https' "$1" -o "$deb"
  echo "$2  $deb" | sha256sum --check --quiet
  manifest=$(dpkg-deb --fsys-tarfile "$deb" |
    tar -xO --wildcards '*/resources/app.asar' |
    grep -aoE "JSON\.parse\('\{\"version\":[^']*claude-code-releases[^']*'\)" |
    sed "s/^JSON\.parse('//; s/')\$//")
  rm -f "$deb"
  [[ $(grep -c . <<<"$manifest") == 1 ]] || die "expected one Claude Code manifest in $1"

  jq -ce --arg platform "$3" '
    .manifest.platforms[$platform] as $p
    | select(.baseUrl | startswith("https://downloads.claude.ai/"))
    | select($p.checksum | test("^[0-9a-f]{64}$"))
    | {
        version: .manifest.version,
        url: "\(.baseUrl)/\(.manifest.version)\(if .manifest.hostPolicy == true then "/desktop" else "" end)/\($platform)/\($p.binary)",
        sha256: $p.checksum
      }
  ' <<<"$manifest" || die "unexpected Claude Code manifest in $1"
}

entry() { # nix-system deb-arch cli-platform
  local index=main/binary-$2/Packages expected latest version filename sha256 current newest cli
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

  # Same .deb as already pinned: keep its CLI pin rather than re-downloading.
  cli=$(jq -c --arg sys "$1" --arg sha256 "$sha256" \
    'if .[$sys].sha256 == $sha256 then .[$sys].cli // empty else empty end' sources.json 2>/dev/null || true)
  [[ -n "$cli" ]] || cli=$(cli_pin "$base/$filename" "$sha256" "$3")

  jq -n --arg sys "$1" --arg version "$version" --arg url "$base/$filename" --arg sha256 "$sha256" \
    --argjson cli "$cli" '{($sys): {$version, $url, $sha256, $cli}}'
}

# Build into the work dir: entry() reads the current sources.json, and a
# failure must leave it untouched.
{
  entry x86_64-linux amd64 linux-x64
  entry aarch64-linux arm64 linux-arm64
} | jq -s 'add' >"$work/sources.json"

[[ $(jq '[.[].version] | unique | length' "$work/sources.json") == 1 ]] ||
  die "architectures disagree on the version: $(jq -c 'map_values(.version)' "$work/sources.json")"
[[ $(jq '[.[].cli.version] | unique | length' "$work/sources.json") == 1 ]] ||
  die "architectures disagree on the Claude Code version: $(jq -c 'map_values(.cli.version)' "$work/sources.json")"

mv "$work/sources.json" sources.json
