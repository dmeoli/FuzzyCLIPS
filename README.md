# FuzzyCLIPS 🔥

> Fuzzy logic for [CLIPS](https://www.clipsrules.net/), **written in pure CLIPS**.

A small, dependency-free fuzzy-logic library you can `load` into any CLIPS 6.4.x
or [clipspy](https://github.com/noxdafox/clipspy) project. It re-implements the
core of the classic **FuzzyCLIPS** (R. Orchard, NRC Canada) — fuzzy sets,
membership functions, fuzzy operators and defuzzification — *without forking the
CLIPS C engine*. That means it runs on stock, modern CLIPS and stays trivially
embeddable and maintainable.

Where the original FuzzyCLIPS weaves fuzzy facts into the RETE engine in C, this
library models a fuzzy set as a **piecewise-linear membership function** (ordered
`(x, μ)` breakpoints) and provides the fuzzy math as ordinary `deffunction`s. The
numerics are **validated against the authentic FuzzyCLIPS 6.10d** via differential
testing (see [Validation](#validation)).

## Why

- **No engine fork.** The original FuzzyCLIPS is tied to CLIPS 6.10 (1998) and is
  hard to keep in sync with modern CLIPS. This is just `.clp` you load.
- **Portable.** Works anywhere CLIPS runs — CLI, embedded, or `clipspy` in Python.
- **Reusable.** Domain-agnostic. Drop `fuzzy.clp` into your project.

## Quick start

```clips
(load "fuzzy.clp")

; A fuzzy set is a piecewise-linear membership function: parallel xs / ys.
; e.g. a triangle peaking at 0 and reaching 0 at 50:
(printout t (fuzzy-centroid (create$ 0 50) (create$ 1.0 0.0)) crlf)
; => 16.6667   (center of gravity)
```

Build membership degrees for the canonical shapes:

```clips
(bind ?xs (create$ 0 10 20 30 40 50 60))
(bind ?ys (fuzzy-triangle-y  ?xs 0 30 60))   ; triangle a=0  b=30 c=60
(bind ?ys (fuzzy-trapezoid-y ?xs 0 20 40 60)) ; trapezoid a=0 b=20 c=40 d=60
(fuzzy-centroid ?xs ?ys)
```

## API (current)

| Function | Purpose |
|---|---|
| `fuzzy-triangle-y  ?xs ?a ?b ?c`    | triangular membership degrees over `?xs` |
| `fuzzy-trapezoid-y ?xs ?a ?b ?c ?d` | trapezoidal membership degrees over `?xs` |
| `fuzzy-centroid ?xs ?ys`            | centroid / center-of-gravity defuzzification (≡ `moment-defuzzify`) |
| `fuzzy-maximum  ?xs ?ys`            | mean-of-maxima defuzzification (≡ `maximum-defuzzify`) |
| `fuzzy-centroid-of ?name`           | defuzzify a stored `fuzzy-set` fact by name |

## Roadmap

- [x] Membership constructors (triangle, trapezoid)
- [x] Defuzzification: centroid + maximum — validated vs the oracle
- [ ] Fuzzy set operators: complement (`1−μ`), union (`max`), intersection (`min`) with crossover points
- [ ] Mamdani inference (fuzzify → implication → aggregation → defuzzify)
- [ ] More membership functions: gaussian, S / Z / Π, singleton
- [ ] `examples/tipper.clp` (the classic tipping problem)

## Validation

Correctness is checked by **differential testing** against the original
FuzzyCLIPS 6.10d, included as a git submodule (oracle only — never shipped):

```bash
git submodule update --init --recursive
./scripts/build-oracle.sh     # builds the 1998 C engine on a modern gcc
./tests/diff_test.sh          # asserts ours == oracle within 1e-4
```

```
case                       ours         oracle    verdict
----------------------------------------------------------
tri_half              16.666667      16.666667       PASS
tri_centered          50.000000      50.000000       PASS
trapezoid             30.000000      30.000000       PASS
tri_skew_left         23.333333      23.333333       PASS
shoulder_right        57.058824      57.058824       PASS
```

Set `CLIPS=/path/to/clips` if `clips` (6.4.x) is not on your `PATH`.

## License

[MIT](LICENSE). The FuzzyCLIPS *algorithms* are due to R. Orchard / NRC Canada;
this is an independent pure-CLIPS implementation. The `third_party/` submodule
retains its own upstream terms and is used only as a test oracle.
