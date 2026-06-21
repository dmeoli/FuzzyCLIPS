#!/usr/bin/env bash
#
# diff_test.sh - Differential test for fuzzy.clp against the authentic
# FuzzyCLIPS 6.10d oracle. Every result our library computes is checked against
# the same quantity computed by the original engine:
#   - ours   : functions in fuzzy.clp, run on stock CLIPS 6.4.x
#   - oracle : the FuzzyCLIPS 6.10d submodule (third_party/fuzzyclips-native)
#
# Sections: defuzzification, set operators, Mamdani inference, curved MFs.
# Build the oracle first: scripts/build-oracle.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/fuzzy.clp"
ORACLE="$ROOT/third_party/fuzzyclips-native/source/fz_clips"
CLIPS="${CLIPS:-clips}"
EPS="${EPS:-1e-4}"          # exact for piecewise-linear; loosen for sampled curves

[[ -x "$ORACLE" ]] || { echo "Oracle missing — run scripts/build-oracle.sh first." >&2; exit 1; }
command -v "$CLIPS" >/dev/null 2>&1 || { echo "CLIPS 6.4.x not found (set \$CLIPS)." >&2; exit 1; }

pass=0; fail=0
ours()   { printf '(load "%s")\n%s\n(exit)\n' "$LIB" "$1" | "$CLIPS" 2>/dev/null | grep -oE 'R=[-0-9.eE]+' | tail -1 | cut -d= -f2; }
oracle() { local f; f="$(mktemp)"; printf '%s\n' "$1" > "$f"
  printf '(load "%s")\n(reset)\n(run)\n(exit)\n' "$f" | "$ORACLE" 2>/dev/null | grep -oE 'R=[-0-9.eE]+' | tail -1 | cut -d= -f2; rm -f "$f"; }
check()  { # name ours oracle [eps]
  local name="$1" o="$2" r="$3" e="${4:-$EPS}" d ok
  if [[ -z "$o" || -z "$r" ]]; then printf "  %-22s %12s %12s   ERROR\n" "$name" "${o:-ERR}" "${r:-ERR}"; fail=$((fail+1)); return; fi
  d="$(awk -v a="$o" -v b="$r" 'BEGIN{d=a-b; print (d<0)?-d:d}')"
  ok="$(awk -v d="$d" -v e="$e" 'BEGIN{print (d<e)?"PASS":"FAIL"}')"
  printf "  %-22s %12.5f %12.5f   %s\n" "$name" "$o" "$r" "$ok"
  if [[ "$ok" == PASS ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
}
hdr() { printf "\n%s\n  %-22s %12s %12s   %s\n" "$1" "case" "ours" "oracle" "verdict"; }

pairs() { paste -d' ' <(echo "$1"|tr ' ' '\n') <(echo "$2"|tr ' ' '\n') | awk '{printf "(%s %s)",$1,$2}'; }

# --- 1. Defuzzification (centroid) — exact for piecewise-linear sets --------
hdr "[1] defuzzification (centroid)"
defuzz_case() { # name xs ys
  local o r
  o="$(ours "(printout t \"R=\" (fuzzy-centroid (create\$ $2) (create\$ $3)) crlf)")"
  r="$(oracle "(deftemplate v 0 100 u ( (s $(pairs "$2" "$3")) )) (defrule t => (printout t \"R=\" (moment-defuzzify (assert (v s))) crlf))")"
  check "$1" "$o" "$r"
}
defuzz_case "tri_half"       "0 50"        "1.0 0.0"
defuzz_case "tri_centered"   "0 50 100"    "0.0 1.0 0.0"
defuzz_case "trapezoid"      "0 20 40 60"  "0.0 1.0 1.0 0.0"
defuzz_case "tri_skew_left"  "0 10 60"     "0.0 1.0 0.0"
defuzz_case "shoulder_right" "0 30 100"    "0.0 1.0 1.0"

# --- 2. Set operators — exact (crossover points inserted) ------------------
hdr "[2] set operators (A=(0,0)(20,1)(50,0) B=(30,0)(80,1)(100,0))"
TERMS="(a (0 0)(20 1)(50 0)) (b (30 0)(80 1)(100 0))"
xsA="0 20 50"; ysA="0 1 0"; xsB="30 80 100"; ysB="0 1 0"
op_oracle(){ oracle "(deftemplate v 0 100 u ( $TERMS )) (defrule t => (printout t \"R=\" (moment-defuzzify (assert (v $1))) crlf))"; }
check "union"        "$(ours "(printout t \"R=\" (fuzzy-centroid (fuzzy-union 0 100 (create\$ $xsA)(create\$ $ysA)(create\$ $xsB)(create\$ $ysB))) crlf)")"        "$(op_oracle 'a or b')"
check "intersection" "$(ours "(printout t \"R=\" (fuzzy-centroid (fuzzy-intersection 0 100 (create\$ $xsA)(create\$ $ysA)(create\$ $xsB)(create\$ $ysB))) crlf)")"  "$(op_oracle 'a and b')"
check "complement"   "$(ours "(printout t \"R=\" (fuzzy-centroid (fuzzy-complement 0 100 (create\$ $xsA)(create\$ $ysA))) crlf)")"                                  "$(op_oracle 'not a')"

# --- 3. Mamdani inference — full pipeline via the tipper consequents -------
hdr "[3] Mamdani aggregate+defuzzify (tipper @ service=9,food=9)"
mam_ours="(bind ?c2 (fuzzy-clip 0 30 (create\$ 5 15 25)(create\$ 0 1 0) 0.2))
(bind ?c3 (fuzzy-clip 0 30 (create\$ 20 30)(create\$ 0 1) 0.8))
(printout t \"R=\" (fuzzy-centroid (fuzzy-aggregate 0 30 ?c2 ?c3)) crlf)"
mam_oracle="(deftemplate tip 0 30 u ( (r2 (5 0)(7 0.2)(23 0.2)(25 0)) (r3 (20 0)(28 0.8)(30 0.8)) ))
(defrule t => (assert (tip r2)) (bind ?f (assert (tip r3))) (printout t \"R=\" (moment-defuzzify ?f) crlf))"
check "tipper(9,9)" "$(ours "$mam_ours")" "$(oracle "$mam_oracle")"

# --- 4. Curved MFs — sampled on a grid, so allow a small tolerance ---------
hdr "[4] curved membership functions (sampled, eps=0.2)"
GRID="$(seq 0 100 | tr '\n' ' ')"
check "S(20,80)"      "$(ours "(printout t \"R=\" (fuzzy-centroid (create\$ $GRID) (fuzzy-s-y (create\$ $GRID) 20 80)) crlf)")" "$(oracle "(deftemplate v 0 100 u ((term (s 20 80)))) (defrule t => (printout t \"R=\" (moment-defuzzify (assert (v term))) crlf))")" 0.2
check "Z(20,80)"      "$(ours "(printout t \"R=\" (fuzzy-centroid (create\$ $GRID) (fuzzy-z-y (create\$ $GRID) 20 80)) crlf)")" "$(oracle "(deftemplate v 0 100 u ((term (z 20 80)))) (defrule t => (printout t \"R=\" (moment-defuzzify (assert (v term))) crlf))")" 0.2
check "PI(c=50,w=30)" "$(ours "(printout t \"R=\" (fuzzy-centroid (create\$ $GRID) (fuzzy-pi-y (create\$ $GRID) 50 30)) crlf)")" "$(oracle "(deftemplate v 0 100 u ((term (pi 30 50)))) (defrule t => (printout t \"R=\" (moment-defuzzify (assert (v term))) crlf))")" 0.2

echo
echo "PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
