#!/usr/bin/env bash
# Fail when the Dockerfile copies from a path that .github/build-inputs does not list.
#
# build.yml publishes only when a listed path changed, so an unlisted COPY source would
# change the image without ever publishing it. Every listed path must also exist.
#
#   scripts/check-build-inputs.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

inputs=()
while IFS= read -r p; do inputs+=("$p"); done < <(grep -vE '^[[:space:]]*(#|$)' .github/build-inputs)
rc=0
for p in "${inputs[@]}"; do
  [ -e "$p" ] || { echo "listed build input '$p' does not exist" >&2; rc=1; }
done

covered() {
  local src=$1 p
  for p in "${inputs[@]}"; do
    [ "$src" = "$p" ] || [[ "$src" == "$p"/* ]] && return 0
  done
  return 1
}

# Join continuation lines, then read the sources of every COPY/ADD that reads the build
# context (a --from= copy reads another stage or image, a URL the network, not this
# repository).
while IFS= read -r line; do
  read -r -a words <<< "$line"
  args=()
  for a in "${words[@]:1}"; do
    case "$a" in
      --from=*) continue 2 ;;
      --*) ;;
      *) args+=("$a") ;;
    esac
  done
  [ "${#args[@]}" -ge 2 ] || continue
  for src in "${args[@]:0:${#args[@]}-1}"; do
    # A remote ADD fetches a URL, not the build context; the Dockerfile pins it.
    case "$src" in http://*|https://*) continue ;; esac
    src=${src#./}; src=${src%/}
    covered "$src" || { echo "Dockerfile copies '$src', which .github/build-inputs does not list" >&2; rc=1; }
  done
done < <(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' Dockerfile | grep -iE '^[[:space:]]*(COPY|ADD)[[:space:]]' | tr -d '[],"')

[ "$rc" = 0 ] && echo "build inputs cover every COPY source: ${inputs[*]}"
exit "$rc"
