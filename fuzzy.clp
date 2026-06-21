;;;===========================================================================
;;; fuzzy.clp - A reusable fuzzy-logic library for standard CLIPS (6.4.x)
;;;
;;;   Pure CLIPS, no engine fork: runs on stock CLIPS / clipspy. The fuzzy math
;;;   is modelled faithfully on FuzzyCLIPS (Orchard, NRC Canada) so results are
;;;   numerically equivalent. A fuzzy set is a piecewise-linear membership
;;;   function stored as ordered breakpoints: two parallel multifields
;;;     xs = strictly increasing universe coordinates
;;;     ys = membership degree in [0,1] at each x
;;;
;;;   Domain-agnostic: reuse it in any project.
;;;
;;;   Provides: membership functions (triangle, trapezoid, gaussian, S/Z/PI,
;;;   singleton), set operators (complement, union, intersection with crossover
;;;   points), defuzzification (centroid, maximum) and Mamdani inference (clip,
;;;   aggregate). All validated against the authentic FuzzyCLIPS 6.10d oracle
;;;   (see scripts/build-oracle.sh and tests/diff_test.sh).
;;;
;;;   Author: Donato Meoli
;;;   License: MIT
;;;===========================================================================

;;****************
;;* DEFTEMPLATES *
;;****************

;; A named fuzzy set over an (optional) linguistic variable, represented by the
;; coordinate pairs of its piecewise-linear membership function.
(deftemplate fuzzy-set
   (slot name)
   (slot var (default nil))
   (multislot xs)
   (multislot ys))

;;****************************
;;* MEMBERSHIP CONSTRUCTORS  *
;;****************************
;; Each returns a multifield of the membership degrees (ys); pair it with the
;; xs you pass in. For the canonical shapes the breakpoints ARE the parameters,
;; so the helpers below return the full (xs ys) interleaved-free representation
;; via create$ of two parts is awkward in CLIPS; instead they assert a fuzzy-set
;; or you build xs/ys directly. The shape helpers return ys given xs.

;; Triangular membership: 0 before a, rises to 1 at b, falls to 0 after c.
(deffunction fuzzy-triangle-y (?xs ?a ?b ?c)
   (bind ?ys (create$))
   (progn$ (?x ?xs)
      (bind ?mu
         (if (or (<= ?x ?a) (>= ?x ?c)) then 0.0
          else (if (<= ?x ?b)
                then (/ (- ?x ?a) (- ?b ?a))
                else (/ (- ?c ?x) (- ?c ?b)))))
      (bind ?ys (create$ ?ys ?mu)))
   ?ys)

;; Trapezoidal membership: 0 before a, rises to 1 over [a,b], flat 1 over [b,c],
;; falls to 0 over [c,d].
(deffunction fuzzy-trapezoid-y (?xs ?a ?b ?c ?d)
   (bind ?ys (create$))
   (progn$ (?x ?xs)
      (bind ?mu
         (if (or (<= ?x ?a) (>= ?x ?d)) then 0.0
          else (if (< ?x ?b) then (/ (- ?x ?a) (- ?b ?a))
                else (if (<= ?x ?c) then 1.0
                      else (/ (- ?d ?x) (- ?d ?c))))))
      (bind ?ys (create$ ?ys ?mu)))
   ?ys)

;;***************************
;;* ACCESSORS & EVALUATION  *
;;***************************

;; A "packed" fuzzy value interleaves coordinates as (x1 y1 x2 y2 ...). The set
;; operations below return packed values; the defuzzifiers accept either the
;; parallel (xs ys) form or a single packed value.
(deffunction fuzzy-px (?packed)
   (bind ?xs (create$)) (bind ?i 1)
   (while (<= ?i (length$ ?packed)) do
      (bind ?xs (create$ ?xs (nth$ ?i ?packed))) (bind ?i (+ ?i 2)))
   ?xs)

(deffunction fuzzy-py (?packed)
   (bind ?ys (create$)) (bind ?i 2)
   (while (<= ?i (length$ ?packed)) do
      (bind ?ys (create$ ?ys (nth$ ?i ?packed))) (bind ?i (+ ?i 2)))
   ?ys)

;; Membership at an arbitrary x by linear interpolation; holds the endpoint
;; value outside the defined breakpoints (FuzzyCLIPS coordinate semantics).
(deffunction fuzzy-eval (?xs ?ys ?x)
   (bind ?n (length$ ?xs))
   (if (<= ?x (nth$ 1 ?xs)) then (return (nth$ 1 ?ys)))
   (if (>= ?x (nth$ ?n ?xs)) then (return (nth$ ?n ?ys)))
   (loop-for-count (?i 1 (- ?n 1)) do
      (bind ?x1 (nth$ ?i ?xs)) (bind ?x2 (nth$ (+ ?i 1) ?xs))
      (if (and (>= ?x ?x1) (<= ?x ?x2)) then
         (bind ?y1 (nth$ ?i ?ys)) (bind ?y2 (nth$ (+ ?i 1) ?ys))
         (if (<= (- ?x2 ?x1) 0) then (return ?y2))
         (return (+ ?y1 (* (- ?y2 ?y1) (/ (- ?x ?x1) (- ?x2 ?x1)))))))
   0.0)

;;********************
;;* DEFUZZIFICATION  *
;;********************

;; Centroid (Center of Gravity) of a piecewise-linear membership function,
;; integrated ANALYTICALLY per segment (exactly as FuzzyCLIPS moment-defuzzify).
;; For each trapezoidal segment (x1,y1)-(x2,y2):
;;   area     = dx * (y1 + y2) / 2
;;   centroid = x1 + dx * (y1 + 2*y2) / (3 * (y1 + y2))
;; Returns sum(area_i * centroid_i) / sum(area_i).
(deffunction fuzzy-centroid (?xs $?ys)
   (if (= (length$ ?ys) 0) then
      (bind ?p ?xs) (bind ?xs (fuzzy-px ?p)) (bind ?ys (fuzzy-py ?p)))
   (bind ?num 0.0)
   (bind ?den 0.0)
   (loop-for-count (?i 1 (- (length$ ?xs) 1)) do
      (bind ?x1 (nth$ ?i ?xs))       (bind ?x2 (nth$ (+ ?i 1) ?xs))
      (bind ?y1 (nth$ ?i ?ys))       (bind ?y2 (nth$ (+ ?i 1) ?ys))
      (bind ?dx (- ?x2 ?x1))
      (bind ?sy (+ ?y1 ?y2))
      (if (and (> ?dx 0) (> ?sy 0)) then
         (bind ?area (* ?dx (/ ?sy 2)))
         (bind ?cx (+ ?x1 (* ?dx (/ (+ ?y1 (* 2 ?y2)) (* 3 ?sy)))))
         (bind ?num (+ ?num (* ?area ?cx)))
         (bind ?den (+ ?den ?area))))
   (if (> ?den 0) then (/ ?num ?den) else 0.0))

;; Maximum defuzzify: mean of the x values where membership is maximal
;; (matches FuzzyCLIPS maximum-defuzzify for plateaus / single peaks).
(deffunction fuzzy-maximum (?xs $?ys)
   (if (= (length$ ?ys) 0) then
      (bind ?p ?xs) (bind ?xs (fuzzy-px ?p)) (bind ?ys (fuzzy-py ?p)))
   (bind ?max 0.0)
   (progn$ (?y ?ys) (if (> ?y ?max) then (bind ?max ?y)))
   (bind ?sum 0.0)
   (bind ?n 0)
   (loop-for-count (?i 1 (length$ ?xs)) do
      (if (>= (nth$ ?i ?ys) (- ?max 1e-9)) then
         (bind ?sum (+ ?sum (nth$ ?i ?xs)))
         (bind ?n (+ ?n 1))))
   (if (> ?n 0) then (/ ?sum ?n) else 0.0))

;; Convenience: defuzzify a stored fuzzy-set fact by name.
(deffunction fuzzy-centroid-of (?name)
   (do-for-fact ((?f fuzzy-set)) (eq ?f:name ?name)
      (return (fuzzy-centroid ?f:xs ?f:ys)))
   0.0)

;;********************
;;* SET OPERATIONS   *
;;********************

;; Ascending comparator for (sort): returns TRUE when ?a must come after ?b.
(deffunction fuzzy-asc (?a ?b) (> ?a ?b))

;; Sorted, de-duplicated merge of x coordinates (plus the universe bounds).
(deffunction fuzzy-merge (?from ?to ?xsA ?xsB)
   (bind ?sorted (sort fuzzy-asc (create$ ?from ?to ?xsA ?xsB)))
   (bind ?out (create$))
   (progn$ (?x ?sorted)
      (if (or (= (length$ ?out) 0) (> ?x (nth$ (length$ ?out) ?out))) then
         (bind ?out (create$ ?out ?x))))
   ?out)

;; x coordinates where membership functions A and B cross inside a grid interval
;; (needed so that max/min of two piecewise-linear functions stays exact).
(deffunction fuzzy-crossovers (?grid ?xsA ?ysA ?xsB ?ysB)
   (bind ?extra (create$))
   (loop-for-count (?i 1 (- (length$ ?grid) 1)) do
      (bind ?g1 (nth$ ?i ?grid)) (bind ?g2 (nth$ (+ ?i 1) ?grid))
      (bind ?d1 (- (fuzzy-eval ?xsA ?ysA ?g1) (fuzzy-eval ?xsB ?ysB ?g1)))
      (bind ?d2 (- (fuzzy-eval ?xsA ?ysA ?g2) (fuzzy-eval ?xsB ?ysB ?g2)))
      (if (< (* ?d1 ?d2) 0) then
         (bind ?xc (+ ?g1 (* (/ ?d1 (- ?d1 ?d2)) (- ?g2 ?g1))))
         (bind ?extra (create$ ?extra ?xc))))
   ?extra)

;; Pointwise combine of two sets over [from,to] with crossover points inserted.
;; ?mode = union (max) | intersect (min). Returns a packed (x1 y1 x2 y2 ...) value.
(deffunction fuzzy-binop (?from ?to ?xsA ?ysA ?xsB ?ysB ?mode)
   (bind ?g (fuzzy-merge ?from ?to ?xsA ?xsB))
   (bind ?grid (fuzzy-merge ?from ?to ?g (fuzzy-crossovers ?g ?xsA ?ysA ?xsB ?ysB)))
   (bind ?packed (create$))
   (progn$ (?x ?grid)
      (bind ?ya (fuzzy-eval ?xsA ?ysA ?x))
      (bind ?yb (fuzzy-eval ?xsB ?ysB ?x))
      (bind ?y (if (eq ?mode union) then (max ?ya ?yb) else (min ?ya ?yb)))
      (bind ?packed (create$ ?packed ?x ?y)))
   ?packed)

(deffunction fuzzy-union (?from ?to ?xsA ?ysA ?xsB ?ysB)
   (fuzzy-binop ?from ?to ?xsA ?ysA ?xsB ?ysB union))

(deffunction fuzzy-intersection (?from ?to ?xsA ?ysA ?xsB ?ysB)
   (fuzzy-binop ?from ?to ?xsA ?ysA ?xsB ?ysB intersect))

;; Standard complement (1 - mu) over [from,to]. Returns a packed value.
(deffunction fuzzy-complement (?from ?to ?xs ?ys)
   (bind ?grid (fuzzy-merge ?from ?to ?xs ?xs))
   (bind ?packed (create$))
   (progn$ (?x ?grid)
      (bind ?packed (create$ ?packed ?x (- 1 (fuzzy-eval ?xs ?ys ?x)))))
   ?packed)

;;************************
;;* MORE MEMBERSHIP MFs  *
;;************************
;; Curved MFs are SAMPLED on the xs grid you pass in (use a fine grid for smooth
;; results). The scalar form gives the degree at one x; the *-y form maps a grid.

;; Gaussian centred at ?c with spread ?sigma.
(deffunction fuzzy-gaussian (?x ?c ?sigma)
   (exp (* -0.5 (** (/ (- ?x ?c) ?sigma) 2))))

;; Zadeh S-curve: 0 below ?a, 1 above ?b, smooth in between (inflection at mid).
(deffunction fuzzy-s (?x ?a ?b)
   (bind ?m (/ (+ ?a ?b) 2)) (bind ?d (- ?b ?a))
   (if (<= ?x ?a) then 0.0
    else (if (>= ?x ?b) then 1.0
          else (if (<= ?x ?m) then (* 2 (** (/ (- ?x ?a) ?d) 2))
                else (- 1 (* 2 (** (/ (- ?x ?b) ?d) 2)))))))

;; Zadeh Z-curve (mirror of S).
(deffunction fuzzy-z (?x ?a ?b) (- 1 (fuzzy-s ?x ?a ?b)))

;; Zadeh PI bell: S up to ?c then Z, half-width ?w.
(deffunction fuzzy-pi (?x ?c ?w)
   (if (<= ?x ?c) then (fuzzy-s ?x (- ?c ?w) ?c)
    else (fuzzy-z ?x ?c (+ ?c ?w))))

(deffunction fuzzy-gaussian-y (?xs ?c ?sigma)
   (bind ?ys (create$)) (progn$ (?x ?xs) (bind ?ys (create$ ?ys (fuzzy-gaussian ?x ?c ?sigma)))) ?ys)
(deffunction fuzzy-s-y (?xs ?a ?b)
   (bind ?ys (create$)) (progn$ (?x ?xs) (bind ?ys (create$ ?ys (fuzzy-s ?x ?a ?b)))) ?ys)
(deffunction fuzzy-z-y (?xs ?a ?b)
   (bind ?ys (create$)) (progn$ (?x ?xs) (bind ?ys (create$ ?ys (fuzzy-z ?x ?a ?b)))) ?ys)
(deffunction fuzzy-pi-y (?xs ?c ?w)
   (bind ?ys (create$)) (progn$ (?x ?xs) (bind ?ys (create$ ?ys (fuzzy-pi ?x ?c ?w)))) ?ys)

;; Singleton: 1 at ?c, 0 elsewhere (on the given grid).
(deffunction fuzzy-singleton-y (?xs ?c)
   (bind ?ys (create$)) (progn$ (?x ?xs) (bind ?ys (create$ ?ys (if (= ?x ?c) then 1.0 else 0.0)))) ?ys)

;;********************
;;* MAMDANI ENGINE   *
;;********************
;; fuzzify  : degree of a crisp ?x in a term = (fuzzy-eval xs ys ?x)
;; implicate: clip a consequent set at firing strength ?alpha (min with constant)
;; aggregate: union of (clipped) consequent sets
;; defuzzify: (fuzzy-centroid <packed>)

;; Mamdani implication (clipping): min(set, alpha) over [from,to]. Returns packed.
(deffunction fuzzy-clip (?from ?to ?xs ?ys ?alpha)
   (fuzzy-intersection ?from ?to ?xs ?ys (create$ ?from ?to) (create$ ?alpha ?alpha)))

;; Aggregate two packed consequent sets by union (max). Returns packed.
(deffunction fuzzy-aggregate (?from ?to ?pa ?pb)
   (fuzzy-union ?from ?to (fuzzy-px ?pa) (fuzzy-py ?pa) (fuzzy-px ?pb) (fuzzy-py ?pb)))
