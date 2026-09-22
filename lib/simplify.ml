open Contract

(* Structural equality is safe here: contracts and observables carry no
   functions and no cycles, because the observable algebra is a closed set of
   constructors. That was the reason for closing it. *)
let equal (a : t) (b : t) = a = b

let rec simplify (c : t) : t =
  match c with
  | Zero | One -> c
  | Give c -> (
      match simplify c with Zero -> Zero | Give inner -> inner | s -> Give s)
  | And (a, b) -> (
      match (simplify a, simplify b) with
      | Zero, s | s, Zero -> s
      | sa, sb -> And (sa, sb))
  | Or (a, b) -> (
      match (simplify a, simplify b) with
      | sa, sb when equal sa sb -> sa
      | sa, sb -> Or (sa, sb))
  | Cond (o, a, b) -> (
      match (simplify a, simplify b) with
      | sa, sb when equal sa sb -> sa
      | sa, sb -> Cond (o, sa, sb))
  | Scale (o, c) -> (
      match (o, simplify c) with
      | _, Zero -> Zero
      | Obs.Konst k, _ when k = 0.0 -> Zero
      | Obs.Konst k, s when k = 1.0 -> s
      | o, Scale (inner, s) -> simplify (Scale (Obs.Mul (o, inner), s))
      | o, s -> Scale (o, s))
  | When (o, c) -> ( match simplify c with Zero -> Zero | s -> When (o, s))
  | Anytime (o, c) -> (
      match simplify c with Zero -> Zero | s -> Anytime (o, s))
  | Until (o, c) -> ( match simplify c with Zero -> Zero | s -> Until (o, s))
