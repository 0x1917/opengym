#!/usr/bin/env bash
# Print the highest source tag belonging to a version.
#
# Reads candidate names on stdin, one per line, and prints `v<version>` or the
# highest `v<version>-<n>`. Prints nothing when none match, and always exits 0 so
# a caller under `set -e` needs no `|| true`.
#
# The tag is the version, with no repository prefix: this repo holds one image, so
# a prefix buys nothing and only makes the tag harder to read.
#
# String matching, not a regex: 1.4.4 must not match 1.4.40, 1x4x4, or
# 1.4.4-beta. The version is compared as literal text, and a rebuild suffix has
# to be all digits.
#
# Used by both the tag step and the release step of `publish.yml`, so the rule
# lives in one place.
set -euo pipefail

version=${1:?usage: version-tag.sh <version>}
base="v${version}"

while IFS= read -r name; do
  case "$name" in
    "$base") printf '%s\n' "$name" ;;
    "$base"-*)
      n=${name#"$base"-}
      case "$n" in
        '' | *[!0-9]*) ;;
        *) printf '%s\n' "$name" ;;
      esac
      ;;
  esac
done | sort -V | tail -n 1
