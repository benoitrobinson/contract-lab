type _ t =
  | Konst : float -> float t
  | Spot : float t
  | Add : float t * float t -> float t
  | Sub : float t * float t -> float t
  | Mul : float t * float t -> float t
  | Max : float t * float t -> float t
  | Ge : float t * float t -> bool t
  | Le : float t * float t -> bool t
  | And : bool t * bool t -> bool t
  | Or : bool t * bool t -> bool t
  | Not : bool t -> bool t
  | Always : bool t
  | AtOrAfter : Date.t -> bool t
  | Before : Date.t -> bool t

type state = { spot : float; today : Date.t }

let rec eval : type a. a t -> state -> a =
 fun o s ->
  match o with
  | Konst k -> k
  | Spot -> s.spot
  | Add (a, b) -> eval a s +. eval b s
  | Sub (a, b) -> eval a s -. eval b s
  | Mul (a, b) -> eval a s *. eval b s
  | Max (a, b) -> Float.max (eval a s) (eval b s)
  | Ge (a, b) -> eval a s >= eval b s
  | Le (a, b) -> eval a s <= eval b s
  | And (a, b) -> eval a s && eval b s
  | Or (a, b) -> eval a s || eval b s
  | Not a -> not (eval a s)
  | Always -> true
  | AtOrAfter d -> Date.compare s.today d >= 0
  | Before d -> Date.compare s.today d < 0

let num f =
  if Float.is_integer f then Printf.sprintf "%.0f" f else Printf.sprintf "%g" f

let rec to_string : type a. a t -> string =
 fun o ->
  match o with
  | Konst k -> num k
  | Spot -> "S"
  | Add (a, b) -> Printf.sprintf "(%s + %s)" (to_string a) (to_string b)
  | Sub (a, b) -> Printf.sprintf "%s - %s" (to_string a) (to_string b)
  | Mul (a, b) -> Printf.sprintf "%s * %s" (to_string a) (to_string b)
  | Max (a, b) -> Printf.sprintf "max(%s, %s)" (to_string a) (to_string b)
  | Ge (a, b) -> Printf.sprintf "%s >= %s" (to_string a) (to_string b)
  | Le (a, b) -> Printf.sprintf "%s <= %s" (to_string a) (to_string b)
  | And (a, b) -> Printf.sprintf "%s and %s" (to_string a) (to_string b)
  | Or (a, b) -> Printf.sprintf "%s or %s" (to_string a) (to_string b)
  | Not a -> Printf.sprintf "not (%s)" (to_string a)
  | Always -> "always"
  | AtOrAfter d -> Printf.sprintf "on or after %s" (Date.to_string d)
  | Before d -> Printf.sprintf "before %s" (Date.to_string d)

let%expect_test "arithmetic evaluates at a node" =
  let s = { spot = 120.0; today = Date.of_ymd 2026 9 22 } in
  Printf.printf "%.2f" (eval (Sub (Spot, Konst 100.0)) s);
  [%expect {| 20.00 |}]

let%expect_test "comparisons produce booleans" =
  let s = { spot = 120.0; today = Date.of_ymd 2026 9 22 } in
  Printf.printf "%b %b"
    (eval (Ge (Spot, Konst 100.0)) s)
    (eval (Le (Spot, Konst 100.0)) s);
  [%expect {| true false |}]

let%expect_test "dates compare against the node's date" =
  let s = { spot = 1.0; today = Date.of_ymd 2026 9 22 } in
  let expiry = Date.of_ymd 2026 12 25 in
  Printf.printf "%b %b" (eval (AtOrAfter expiry) s) (eval (Before expiry) s);
  [%expect {| false true |}]

let%expect_test "an observable prints as itself" =
  print_string (to_string (Max (Sub (Spot, Konst 100.0), Konst 0.0)));
  [%expect {| max(S - 100, 0) |}]
