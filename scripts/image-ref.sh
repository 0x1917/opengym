#!/usr/bin/env bash
# Print an upstream image ref, built from the repository ARG in the Dockerfile.
#
#   scripts/image-ref.sh OPENGYM_API_REPO            -> ghcr.io/.../opengym-api:<pinned>
#   scripts/image-ref.sh OPENGYM_API_REPO 1.4.3      -> ghcr.io/.../opengym-api:1.4.3
#
# The repository half lives in exactly one place, the Dockerfile ARG, so the
# workflows stop carrying their own copy of the upstream path.
set -euo pipefail

arg=${1:?usage: image-ref.sh <REPO_ARG> [version]}
root=$(cd "$(dirname "$0")/.." && pwd)
dockerfile="$root/Dockerfile"

repo=$(sed -n "s/^ARG ${arg}=//p" "$dockerfile" | head -1)
[ -n "$repo" ] || { echo "no ARG $arg in $dockerfile" >&2; exit 1; }

version=${2:-$(sed -n 's/^ARG UPSTREAM_VERSION=//p' "$dockerfile" | head -1)}
printf '%s:%s\n' "$repo" "$version"
