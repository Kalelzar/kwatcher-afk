#!/usr/bin/env bash
# Submodule bump + depsHash refresh in dependency order — thin wrapper over
# kw-nix's update-fleet.sh, which derives the graph from the submodule tree.
# COMMITS AND PUSHES in every vendored package repo and this repo — run
# deliberately. This repo deliberately has no flake.lock; update-fleet.sh
# keeps it that way (inputs float, only depsHash is maintained in place).
# See update-fleet.sh for flags (--dry-run, --no-build, --no-push, --init).
#
#   nix/update-all.sh [flags]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KW_NIX="${KW_NIX:-$HOME/Code/nix/kw-nix}"

exec "$KW_NIX/scripts/update-fleet.sh" "$@" "$ROOT"
