type model = {
  s0 : float;
  r : float;
  sigma : float;
  today : Date.t;
  horizon : Date.t;
  steps : int;
  paths : int;
  seed : int;
}

exception Unsupported of string

let rec has_choice (c : Contract.t) =
  match c with
  | Zero | One -> false
  | Or _ | Anytime _ -> true
  | Give c | Scale (_, c) | When (_, c) | Until (_, c) -> has_choice c
  | And (a, b) -> has_choice a || has_choice b
  | Cond (_, a, b) -> has_choice a || has_choice b

let dt m = Date.year_fraction m.today m.horizon /. float_of_int m.steps

let date_at m i =
  Date.add_days m.today
    (int_of_float (Float.round (float_of_int i *. dt m *. 365.0)))

(* Box-Muller on the stdlib generator. OCaml 5's Random is LXM and splittable,
   so a fixed seed reproduces a run on any machine running the same compiler. *)
let normal rng =
  let u1 = Float.max 1e-12 (Random.State.float rng 1.0) in
  let u2 = Random.State.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)

let simulate m rng =
  let dt = dt m in
  let drift = (m.r -. (0.5 *. m.sigma *. m.sigma)) *. dt in
  let vol = m.sigma *. sqrt dt in
  let path = Array.make (m.steps + 1) m.s0 in
  for i = 1 to m.steps do
    path.(i) <- path.(i - 1) *. exp (drift +. (vol *. normal rng))
  done;
  path

let state m path i : Obs.state = { spot = path.(i); today = date_at m i }

(* Present value at step `i`, of a contract whose cashflows after step `limit`
   have been cancelled by an enclosing `until`. *)
let rec pv m path ~limit i (c : Contract.t) =
  match c with
  | Zero -> 0.0
  | One -> 1.0
  | Give c -> -.pv m path ~limit i c
  | And (a, b) -> pv m path ~limit i a +. pv m path ~limit i b
  | Or _ -> raise (Unsupported "or")
  | Anytime _ -> raise (Unsupported "anytime")
  | Scale (o, c) -> Obs.eval o (state m path i) *. pv m path ~limit i c
  | Cond (o, a, b) ->
      if Obs.eval o (state m path i) then pv m path ~limit i a
      else pv m path ~limit i b
  | When (o, c) -> (
      match first_true m path ~from:i ~until:limit o with
      | None -> 0.0
      | Some j ->
          exp (-.m.r *. dt m *. float_of_int (j - i)) *. pv m path ~limit j c)
  | Until (o, c) -> (
      match first_true m path ~from:i ~until:limit o with
      | None -> pv m path ~limit i c
      | Some j -> if j <= i then 0.0 else pv m path ~limit:(j - 1) i c)

and first_true m path ~from ~until o =
  let rec go i =
    if i > until then None
    else if Obs.eval o (state m path i) then Some i
    else go (i + 1)
  in
  go from

let price m c =
  if has_choice c then raise (Unsupported "contract contains a holder choice");
  let rng = Random.State.make [| m.seed |] in
  let sum = ref 0.0 and sum_sq = ref 0.0 in
  for _ = 1 to m.paths do
    let path = simulate m rng in
    let v = pv m path ~limit:m.steps 0 c in
    sum := !sum +. v;
    sum_sq := !sum_sq +. (v *. v)
  done;
  let n = float_of_int m.paths in
  let mean = !sum /. n in
  let var = Float.max 0.0 ((!sum_sq /. n) -. (mean *. mean)) in
  (mean, sqrt (var /. n))

let%expect_test "contracts with a choice are refused" =
  let c = Products.american_put ~strike:40.0 in
  Printf.printf "%b %b" (has_choice c)
    (has_choice
       (Products.european_call ~strike:100.0 ~expiry:(Date.of_ymd 2027 1 1)));
  [%expect {| true false |}]

let%expect_test
    "the European call agrees with Black-Scholes within three standard errors" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m =
    {
      s0 = 100.0;
      r = 0.05;
      sigma = 0.2;
      today;
      horizon;
      steps = 50;
      paths = 200_000;
      seed = 7;
    }
  in
  let p, se = price m (Products.european_call ~strike:100.0 ~expiry:horizon) in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%b" (Float.abs (p -. bs) < 3.0 *. se);
  [%expect {| true |}]

let%expect_test
    "the digital agrees with its closed form within three standard errors" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m =
    {
      s0 = 100.0;
      r = 0.05;
      sigma = 0.2;
      today;
      horizon;
      steps = 50;
      paths = 200_000;
      seed = 11;
    }
  in
  let p, se =
    price m (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0)
  in
  let closed =
    Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0
  in
  Printf.printf "%b" (Float.abs (p -. closed) < 3.0 *. se);
  [%expect {| true |}]

let%expect_test "a knock-out is worth less than the vanilla it wraps" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m =
    {
      s0 = 100.0;
      r = 0.05;
      sigma = 0.2;
      today;
      horizon;
      steps = 250;
      paths = 100_000;
      seed = 3;
    }
  in
  let ko, _ =
    price m
      (Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry:horizon)
  in
  let vanilla, _ =
    price m (Products.european_call ~strike:100.0 ~expiry:horizon)
  in
  Printf.printf "%b" (ko < vanilla -. 0.5);
  [%expect {| true |}]

let%expect_test "the same seed gives the same price" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m =
    {
      s0 = 100.0;
      r = 0.05;
      sigma = 0.2;
      today;
      horizon;
      steps = 20;
      paths = 5_000;
      seed = 42;
    }
  in
  let c = Products.european_call ~strike:100.0 ~expiry:horizon in
  Printf.printf "%b" (fst (price m c) = fst (price m c));
  [%expect {| true |}]
