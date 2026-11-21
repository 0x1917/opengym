#!/usr/bin/env bash
# Print the highest source tag of one version, or of the whole series.
#
#   version-tag.sh <version>   < tags   # v<version> or its highest rebuild
#   version-tag.sh --max       < tags   # the highest tag overall
#
# Reads candidate names on stdin, one per line. Prints nothing when none match, and
# always exits 0 so a caller under `set -e` needs no `|| true`.
#
# Tags are v<x.y.z> for the first publish of a release and v<x.y.z>-r<n> for a
# rebuild of it, the scheme every image repository here uses. The older v<x.y.z>-<n>
# rebuild form is still read, so tags published before the switch keep their place:
# rebuild numbers are compared as numbers across both forms (-1 < -r2), never as text.
#
# The tag is the version, with no repository prefix: this repo holds one image, so
# a prefix buys nothing and only makes the tag harder to read.
#
# Exact matching: 1.4.4 must not match 1.4.40, 1x4x4, or 1.4.4-beta, and a rebuild
# suffix has to be all digits after the optional r.
#
# Used by the scope check in `build.yml` and by the recheck, tag and release steps
# of `publish.yml`, so the rule lives in one place.
set -euo pipefail

want=${1:?usage: version-tag.sh <version> | --max}

while IFS= read -r name; do
  [[ "$name" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-r?([0-9]+))?$ ]] || continue
  version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  [ "$want" = --max ] || [ "$version" = "$want" ] || continue
  printf '%s %s %s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
    "${BASH_REMATCH[5]:-0}" "$name"
done | sort -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1 | awk '{print $5}'
