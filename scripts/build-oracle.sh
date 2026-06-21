#!/usr/bin/env bash
#
# build-oracle.sh — Build the authentic FuzzyCLIPS 6.10d engine (Orchard, NRC
# Canada) used ONLY as a numerical oracle to differential-test this pure-CLIPS
# library (fuzzy.clp). It is a dev/test dependency: never installed system-wide.
#
# Source: git submodule third_party/fuzzyclips-native (rorchard/FuzzyCLIPS).
# That code is 1998-era C; the flags below let it compile on a modern gcc:
#   -fcommon            tentative global definitions shared across files
#   -std=gnu89          old C dialect the sources were written against
#   -w                  silence the (expected) legacy warnings
#   -O1 -fno-strict-aliasing  safe optimisation for old pointer aliasing
#
# Output: third_party/fuzzyclips-native/source/fz_clips
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/third_party/fuzzyclips-native/source"

if [[ ! -d "$SRC" ]]; then
  echo "error: oracle submodule missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

cd "$SRC"
make -f Makefile.cl clean >/dev/null 2>&1 || true
make -f Makefile.cl fz_clips \
  CC=gcc \
  CFLAGS="-c -w -O1 -fcommon -std=gnu89 -fno-strict-aliasing"

echo
echo "Built oracle: $SRC/fz_clips"

# Self-test: triangular set (0,1)->(50,0) has centroid 16.6667.
selftest="$(mktemp)"
cat > "$selftest" <<'EOF'
(deftemplate _selftest 0 100 u ((s (0 1.0) (50 0.0))))
(defrule _t => (printout t "SELFTEST-MD=" (moment-defuzzify (assert (_selftest s))) crlf))
EOF
printf '(load "%s")\n(reset)\n(run)\n(exit)\n' "$selftest" \
  | "$SRC/fz_clips" 2>/dev/null | grep -E 'SELFTEST-MD=' || echo "WARNING: self-test produced no defuzzify output"
rm -f "$selftest"
