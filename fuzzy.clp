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
;;;   Implemented so far: membership-function constructors (triangle, trapezoid)
;;;   and defuzzification (centroid / maximum), validated against the authentic
;;;   FuzzyCLIPS 6.10d oracle (see scripts/build-oracle.sh and tests/). Set
;;;   operations (min/max/complement) and Mamdani inference are the next increment.
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

;;********************
;;* DEFUZZIFICATION  *
;;********************

;; Centroid (Center of Gravity) of a piecewise-linear membership function,
;; integrated ANALYTICALLY per segment (exactly as FuzzyCLIPS moment-defuzzify).
;; For each trapezoidal segment (x1,y1)-(x2,y2):
;;   area     = dx * (y1 + y2) / 2
;;   centroid = x1 + dx * (y1 + 2*y2) / (3 * (y1 + y2))
;; Returns sum(area_i * centroid_i) / sum(area_i).
(deffunction fuzzy-centroid (?xs ?ys)
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
(deffunction fuzzy-maximum (?xs ?ys)
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
