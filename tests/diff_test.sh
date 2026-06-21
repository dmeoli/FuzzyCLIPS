#!/usr/bin/env bash
#
# diff_test.sh - Differential test for fuzzy.clp against the authentic
# FuzzyCLIPS 6.10d oracle. For each piecewise-linear membership function it
# computes the centroid (moment) defuzzification two ways and asserts they match:
#   - ours   : fuzzy-centroid in fuzzy.clp, run on stock CLIPS 6.4.x
#   - oracle : moment-defuzzify in third_party/fuzzyclips-native (FuzzyCLIPS 6.10d)
#
# Build the oracle first: scripts/build-oracle.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/fuzzy.clp"
ORACLE="$ROOT/third_party/fuzzyclips-native/source/fz_clips"
CLIPS="${CLIPS:-clips}"
EPS="1e-4"

[[ -x "$ORACLE" ]] || { echo "Oracle missing — run scripts/build-oracle.sh first." >&2; exit 1; }
command -v "$CLIPS" >/dev/null 2>&1 || { echo "CLIPS 6.4.x not found (set \$CLIPS)." >&2; exit 1; }

# Each case: "name | xs (space-sep) | ys (space-sep)"
cases=(
  "tri_half        | 0 50        | 1.0 0.0"
  "tri_centered    | 0 50 100    | 0.0 1.0 0.0"
  "trapezoid       | 0 20 40 60  | 0.0 1.0 1.0 0.0"
  "tri_skew_left   | 0 10 60     | 0.0 1.0 0.0"
  "shoulder_right  | 0 30 100    | 0.0 1.0 1.0"
)

ours() { # xs ; ys
  local xs="$1" ys="$2"
  printf '(load "%s")\n(printout t "RES=" (fuzzy-centroid (create$ %s) (create$ %s)) crlf)\n(exit)\n' \
    "$LIB" "$xs" "$ys" | "$CLIPS" 2>/dev/null | grep -oE 'RES=[-0-9.eE]+' | head -1 | cut -d= -f2
}

oracle() { # xs ; ys
  local xs=($1) ys=($2)
  local from="${xs[0]}" to="${xs[${#xs[@]}-1]}" pairs=""
  for i in "${!xs[@]}"; do pairs+="(${xs[$i]} ${ys[$i]})"; done
  printf '(deftemplate v %s %s u ( (s %s) ))\n(defrule t => (printout t "RES=" (moment-defuzzify (assert (v s))) crlf))\n' \
    "$from" "$to" "$pairs" > /tmp/_oracle_case.clp
  printf '(load "/tmp/_oracle_case.clp")\n(reset)\n(run)\n(exit)\n' \
    | "$ORACLE" 2>/dev/null | grep -oE 'RES=[-0-9.eE]+' | head -1 | cut -d= -f2
}

pass=0; fail=0
printf "%-16s %14s %14s %10s\n" "case" "ours" "oracle" "verdict"
printf '%.0s-' {1..58}; echo
for c in "${cases[@]}"; do
  IFS='|' read -r name xs ys <<< "$c"
  name="$(echo "$name" | xargs)"; xs="$(echo "$xs" | xargs)"; ys="$(echo "$ys" | xargs)"
  o="$(ours "$xs" "$ys")"; r="$(oracle "$xs" "$ys")"
  if [[ -z "$o" || -z "$r" ]]; then
    printf "%-16s %14s %14s %10s\n" "$name" "${o:-ERR}" "${r:-ERR}" "ERROR"; fail=$((fail+1)); continue
  fi
  d="$(awk -v a="$o" -v b="$r" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')"
  ok="$(awk -v d="$d" -v e="$EPS" 'BEGIN{print (d<e)?"PASS":"FAIL"}')"
  printf "%-16s %14.6f %14.6f %10s\n" "$name" "$o" "$r" "$ok"
  if [[ "$ok" == PASS ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
done
echo
echo "PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
