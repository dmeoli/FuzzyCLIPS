# FuzzyCLIPS

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

## API

**Membership functions** — `*-y` forms return the membership degrees over a grid `?xs`:

| Function | Shape |
|---|---|
| `fuzzy-triangle-y  ?xs ?a ?b ?c`    | triangular |
| `fuzzy-trapezoid-y ?xs ?a ?b ?c ?d` | trapezoidal |
| `fuzzy-gaussian-y  ?xs ?c ?sigma`   | gaussian (sampled) |
| `fuzzy-s-y / fuzzy-z-y ?xs ?a ?b`   | Zadeh S- / Z-curve (sampled) |
| `fuzzy-pi-y ?xs ?c ?w`              | Zadeh Π bell (sampled) |
| `fuzzy-singleton-y ?xs ?c`          | singleton spike |

**Set operators** (over universe `?from..?to`, return a *packed* `(x1 y1 x2 y2 …)` value, crossover points inserted):

| Function | Op |
|---|---|
| `fuzzy-complement ?from ?to ?xs ?ys`           | `1 − μ` |
| `fuzzy-union ?from ?to ?xsA ?ysA ?xsB ?ysB`    | `max` |
| `fuzzy-intersection ?from ?to ?xsA ?ysA ?xsB ?ysB` | `min` |

**Mamdani inference & defuzzification:**

| Function | Purpose |
|---|---|
| `fuzzy-eval ?xs ?ys ?x`                | membership of a crisp `?x` (fuzzify) |
| `fuzzy-clip ?from ?to ?xs ?ys ?alpha`  | implication: clip a consequent at firing strength `?alpha` |
| `fuzzy-aggregate ?from ?to ?pa ?pb`    | aggregate two (clipped) consequents by union |
| `fuzzy-centroid …` / `fuzzy-maximum …` | defuzzify — accept `(?xs ?ys)` **or** a packed value (≡ `moment-` / `maximum-defuzzify`) |
| `fuzzy-centroid-of ?name`              | defuzzify a stored `fuzzy-set` fact by name |

See [`examples/tipper.clp`](examples/tipper.clp) for a full fuzzify → rules → implication → aggregation → defuzzification pipeline.

## Roadmap

- [x] Membership constructors (triangle, trapezoid)
- [x] Defuzzification: centroid + maximum — validated vs the oracle
- [x] Fuzzy set operators: complement (`1−μ`), union (`max`), intersection (`min`) with crossover points
- [x] Mamdani inference (fuzzify → implication → aggregation → defuzzify)
- [x] More membership functions: gaussian, S / Z / Π, singleton
- [x] `examples/tipper.clp` (the classic tipping problem)

## Validation

Correctness is checked by **differential testing** against the original
FuzzyCLIPS 6.10d, included as a git submodule (oracle only — never shipped):

```bash
git submodule update --init --recursive
./scripts/build-oracle.sh     # builds the 1998 C engine on a modern gcc
./tests/diff_test.sh          # asserts ours == oracle
```

The piecewise-linear core (defuzzification, set operators, Mamdani aggregation)
matches the oracle to ~13 significant digits; curved MFs are *sampled*, so they
converge to the oracle within a small tolerance.

```
[1] defuzzification (centroid)      ours       oracle   verdict
  tri_half / tri_centered / trapezoid / skew / shoulder        PASS
[2] set operators
  union 50.97826 / intersection 40.83333 / complement 58.88889 PASS
[3] Mamdani aggregate+defuzzify
  tipper(9,9)            21.53419     21.53419               PASS
[4] curved membership functions (sampled, eps=0.2)
  S / Z / PI                                                  PASS

PASS=12 FAIL=0
```

Set `CLIPS=/path/to/clips` if `clips` (6.4.x) is not on your `PATH`.

## License

[MIT](LICENSE). The FuzzyCLIPS *algorithms* are due to R. Orchard / NRC Canada;
this is an independent pure-CLIPS implementation. The `third_party/` submodule
retains its own upstream terms and is used only as a test oracle.
