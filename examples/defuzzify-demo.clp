;;;===========================================================================
;;; defuzzify-demo.clp - Minimal usage demo for fuzzy.clp
;;;
;;;   Run from the repo root:
;;;     clips -f examples/defuzzify-demo.clp      (CLIPS 6.4.x)
;;;
;;;   Shows building membership degrees for canonical shapes and defuzzifying
;;;   them. (Set operators and Mamdani inference are on the roadmap.)
;;;
;;;   Author: Donato Meoli
;;;===========================================================================

(load "fuzzy.clp")

(printout t crlf "=== fuzzy.clp defuzzification demo ===" crlf crlf)

; A coarse universe of discourse 0..100.
(bind ?xs (create$ 0 10 20 30 40 50 60 70 80 90 100))

; Triangle peaking at 30.
(bind ?tri (fuzzy-triangle-y ?xs 0 30 60))
(printout t "triangle(0,30,60)  centroid = " (fuzzy-centroid ?xs ?tri)
            "  maximum = " (fuzzy-maximum ?xs ?tri) crlf)

; Trapezoid with a plateau over [20,40].
(bind ?trap (fuzzy-trapezoid-y ?xs 0 20 40 60))
(printout t "trapezoid(0,20,40,60) centroid = " (fuzzy-centroid ?xs ?trap)
            "  maximum = " (fuzzy-maximum ?xs ?trap) crlf)

; Stored fuzzy-set fact, defuzzified by name.
(assert (fuzzy-set (name hot) (xs 0 50 100) (ys 0.0 0.0 1.0)))
(printout t "stored set 'hot'   centroid = " (fuzzy-centroid-of hot) crlf)

(printout t crlf "done." crlf)
(exit)
