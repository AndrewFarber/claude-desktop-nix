# Tools come from the dev shell: `nix develop`, or prefix with `nix develop -c`.

# List available recipes
default:
    @just --list

# Check formatting, anti-patterns, dead code, shell scripts and workflows
lint:
    nixfmt --check $(git ls-files '*.nix')
    statix check .
    deadnix --fail .
    shellcheck $(git ls-files '*.sh')
    actionlint

# Format all Nix files
fmt:
    nixfmt $(git ls-files '*.nix')

# Evaluate the flake for every supported system
check:
    nix flake check --all-systems

# Build the package for this machine (creates ./result)
build:
    nix build -L

# Build and launch the app
run *args:
    nix run . -- {{ args }}

# Pull the newest version and hashes from Anthropic's signed apt repo
update:
    .github/update-sources.sh
    git diff --stat sources.json
