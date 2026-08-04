#!/usr/bin/env bash
set -euo pipefail
repo="${1:-$HOME/schema-variant-compare}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/schema-variant-compare"
cp -a "$root/." "$repo/."
printf 'Updated %s\n' "$repo"
