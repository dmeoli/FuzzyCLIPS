;;;===========================================================================
;;; tipper.clp - The classic fuzzy "tipping" problem, built on fuzzy.clp
;;;
;;;   Two crisp inputs (service, food quality on 0..10) -> a crisp tip (0..30%)
;;;   via a full Mamdani pipeline: fuzzify -> rule strengths -> implication
;;;   (clip) -> aggregation (union) -> centroid defuzzification.
;;;
;;;   Run from the repo root:
;;;     clips -f examples/tipper.clp
;;;
;;;   Author: Donato Meoli
;;;===========================================================================

(load "fuzzy.clp")

;; --- Input terms (universe 0..10) ----------------------------------------
;; service: poor (1->0 over 0..5), good (triangle at 5), excellent (0->1 over 5..10)
;; food:    rancid (1->0 over 0..5), delicious (0->1 over 5..10)
(deffunction tip (?service ?food)
   (bind ?poor      (fuzzy-eval (create$ 0 5)    (create$ 1 0)   ?service))
   (bind ?good      (fuzzy-eval (create$ 0 5 10) (create$ 0 1 0) ?service))
   (bind ?excellent (fuzzy-eval (create$ 5 10)   (create$ 0 1)   ?service))
   (bind ?rancid    (fuzzy-eval (create$ 0 5)    (create$ 1 0)   ?food))
   (bind ?delicious (fuzzy-eval (create$ 5 10)   (create$ 0 1)   ?food))

   ;; --- Rules (firing strengths) ------------------------------------------
   ;; R1: service poor  OR food rancid     -> tip cheap
   ;; R2: service good                     -> tip average
   ;; R3: service excellent OR food delicious -> tip generous
   (bind ?a1 (max ?poor ?rancid))
   (bind ?a2 ?good)
   (bind ?a3 (max ?excellent ?delicious))

   ;; --- Output terms (universe 0..30) clipped at each firing strength ------
   (bind ?cheap    (fuzzy-clip 0 30 (create$ 0 10)    (create$ 1 0)   ?a1))
   (bind ?average  (fuzzy-clip 0 30 (create$ 5 15 25) (create$ 0 1 0) ?a2))
   (bind ?generous (fuzzy-clip 0 30 (create$ 20 30)   (create$ 0 1)   ?a3))

   ;; --- Aggregate (union) and defuzzify (centroid) ------------------------
   (bind ?agg (fuzzy-aggregate 0 30 ?cheap ?average))
   (bind ?agg (fuzzy-aggregate 0 30 ?agg ?generous))
   (fuzzy-centroid ?agg))

(printout t crlf "=== fuzzy tipper (Mamdani) ===" crlf)
(printout t "poor service, bad food   (2,3) -> tip " (tip 2 3) "%" crlf)
(printout t "ok service, ok food      (5,5) -> tip " (tip 5 5) "%" crlf)
(printout t "great service, great food (9,9) -> tip " (tip 9 9) "%" crlf)
(exit)
