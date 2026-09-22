(** The combinator algebra of Peyton Jones, Eber and Seward. [One] is one unit
    of the single numeraire currency: multi-currency needs FX observables and is
    out of scope. *)
type t =
  | Zero
  | One
  | Give of t
  | And of t * t
  | Or of t * t
  | Cond of bool Obs.t * t * t
  | Scale of float Obs.t * t
  | When of bool Obs.t * t
  | Anytime of bool Obs.t * t
  | Until of bool Obs.t * t

let rec to_string c =
  match c with
  | Zero -> "zero"
  | One -> "one"
  | Give c -> Printf.sprintf "give (%s)" (to_string c)
  | And (a, b) -> Printf.sprintf "(%s) and (%s)" (to_string a) (to_string b)
  | Or (a, b) -> Printf.sprintf "(%s) or (%s)" (to_string a) (to_string b)
  | Cond (o, a, b) ->
      Printf.sprintf "if (%s) then %s else %s" (Obs.to_string o) (to_string a)
        (to_string b)
  | Scale (o, c) ->
      Printf.sprintf "scale %s of %s" (Obs.to_string o) (to_string c)
  | When (o, c) -> Printf.sprintf "when (%s) %s" (Obs.to_string o) (to_string c)
  | Anytime (o, c) ->
      Printf.sprintf "anytime (%s) %s" (Obs.to_string o) (to_string c)
  | Until (o, c) ->
      Printf.sprintf "until (%s) (%s)" (Obs.to_string o) (to_string c)
