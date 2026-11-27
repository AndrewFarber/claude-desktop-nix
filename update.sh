#!/usr/bin/env bash
# Bump package.nix to the newest claude-desktop in Anthropic's apt repo.
set -euo pipefail
cd "$(dirname "$0")"

index=https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages

read -r version sha256 < <(
  curl -fsSL "$index" | awk '
    /^Version: / { v = $2 }
    /^SHA256: / { print v, $2 }
  ' | sort -V | tail -1
)

current=$(sed -nE 's/^  version = "(.*)";/\1/p' package.nix)
if [[ "$version" == "$current" ]]; then
  echo "Already at $current"
  exit 0
fi

sed -i -E \
  -e "s/^  version = \".*\";/  version = \"$version\";/" \
  -e "s/^    sha256 = \".*\";/    sha256 = \"$sha256\";/" \
  package.nix

echo "Updated $current -> $version"
