#!/bin/bash
# Computes the next kube-nfv fork tag for a given upstream base version.
#
# Fork tags follow: v<upstream-base>-kubenfv.<N>, e.g. v1.6.0-kubenfv.1
# Given a base (e.g. v1.6.0) this prints the next tag: the highest existing
# -kubenfv.N for that base + 1, or .1 if none exist yet.
#
# Usage: hack/release/next-fork-version.sh v1.6.0
set -euo pipefail

BASE="${1:-}"
if [ -z "${BASE}" ]; then
    echo "ERROR: upstream base version required, e.g. $0 v1.6.0" >&2
    exit 1
fi

# Normalize to a leading 'v'.
case "${BASE}" in
    v*) ;;
    *) BASE="v${BASE}" ;;
esac

# Highest existing N for this base (0 if none).
LAST_N=$(git tag --list "${BASE}-kubenfv.*" \
    | sed -n "s/^${BASE}-kubenfv\.\([0-9]\+\)$/\1/p" \
    | sort -n \
    | tail -1)
LAST_N="${LAST_N:-0}"

echo "${BASE}-kubenfv.$((LAST_N + 1))"
