type model = {
  s0 : float;
  r : float;
  sigma : float;
  today : Date.t;
  horizon : Date.t;
  steps : int;
}

type process = float array array
(** [process.(i).(j)] is the value at step [i] after [j] up moves. *)

let dt m = Date.year_fraction m.today m.horizon /. float_of_int m.steps
let up m = exp (m.sigma *. sqrt (dt m))

let p_up m =
  let u = up m in
  let d = 1.0 /. u in
  (exp (m.r *. dt m) -. d) /. (u -. d)

let discount m = exp (-.m.r *. dt m)
let spot m i j = m.s0 *. (up m ** float_of_int ((2 * j) - i))

let date_at m i =
  Date.add_days m.today
    (int_of_float (Float.round (float_of_int i *. dt m *. 365.0)))

let state m i j : Obs.state = { spot = spot m i j; today = date_at m i }
let empty m = Array.init (m.steps + 1) (fun i -> Array.make (i + 1) 0.0)
let const m v = Array.init (m.steps + 1) (fun i -> Array.make (i + 1) v)
let map f (a : process) : process = Array.map (Array.map f) a

let map2 f (a : process) (b : process) : process =
  Array.mapi (fun i row -> Array.mapi (fun j x -> f x b.(i).(j)) row) a

let obs_process : type a. model -> a Obs.t -> a array array =
 fun m o ->
  Array.init (m.steps + 1) (fun i ->
      Array.init (i + 1) (fun j -> Obs.eval o (state m i j)))

(** Discounted expectation of the next step, taken from [v]. *)
let cont m (v : process) i j =
  let p = p_up m in
  discount m *. ((p *. v.(i + 1).(j + 1)) +. ((1.0 -. p) *. v.(i + 1).(j)))

(** [when o c]: acquire [c] at the first node where [o] holds. *)
let disc_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then v.(n).(j) else 0.0)
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      out.(i).(j) <- (if cond.(i).(j) then v.(i).(j) else cont m out i j)
    done
  done;
  out

(** [anytime o c]: the Snell envelope, exercise when it beats continuation. *)
let snell_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then v.(n).(j) else 0.0)
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      let continuation = cont m out i j in
      out.(i).(j) <-
        (if cond.(i).(j) then Float.max v.(i).(j) continuation else continuation)
    done
  done;
  out

(** The cash [v] pays at a node, recovered from its own process: what it is
    worth now, less what its future is worth. Zero everywhere except where the
    contract actually pays. *)
let local_cash m (v : process) i j =
  if i = m.steps then v.(m.steps).(j) else v.(i).(j) -. cont m v i j

(** [until o c]: [c], abandoned at the first node where [o] holds. The recursion
    matters: zeroing the value process pointwise leaves the parent nodes with
    the unbarriered value, which is the European price, and is wrong.
    [absorb_pointwise] below exists to demonstrate exactly that. *)
let absorb_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then 0.0 else v.(n).(j))
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      out.(i).(j) <-
        (if cond.(i).(j) then 0.0 else local_cash m v i j +. cont m out i j)
    done
  done;
  out

let absorb_pointwise (cond : bool array array) (v : process) : process =
  Array.mapi
    (fun i row -> Array.mapi (fun j x -> if cond.(i).(j) then 0.0 else x) row)
    v

let select (cond : bool array array) (a : process) (b : process) : process =
  Array.mapi
    (fun i row ->
      Array.mapi (fun j c -> if c then a.(i).(j) else b.(i).(j)) row)
    cond

let rec value m (c : Contract.t) : process =
  match c with
  | Zero -> const m 0.0
  | One -> const m 1.0
  | Give c -> map (fun v -> -.v) (value m c)
  | And (a, b) -> map2 ( +. ) (value m a) (value m b)
  | Or (a, b) -> map2 Float.max (value m a) (value m b)
  | Cond (o, a, b) -> select (obs_process m o) (value m a) (value m b)
  | Scale (o, c) -> map2 ( *. ) (obs_process m o) (value m c)
  | When (o, c) -> disc_op m (obs_process m o) (value m c)
  | Anytime (o, c) -> snell_op m (obs_process m o) (value m c)
  | Until (o, c) -> absorb_op m (obs_process m o) (value m c)

let price m c = (value m c).(0).(0)

(** Boyle and Lau (1994): put a layer of the tree on the barrier, or the price
    oscillates with the step count as the barrier drifts between layers. Returns
    the largest aligned step count at or below [max_steps]. *)
let boyle_lau_steps ~s ~h ~sigma ~t ~max_steps =
  let ratio = log (s /. h) in
  if ratio <= 0.0 then max_steps
  else begin
    let best = ref 1 in
    let k = ref 1 in
    let continue_ = ref true in
    while !continue_ do
      let n =
        int_of_float
          (float_of_int (!k * !k) *. sigma *. sigma *. t /. (ratio *. ratio))
      in
      if n > max_steps then continue_ := false
      else begin
        if n > !best then best := n;
        incr k
      end
    done;
    Stdlib.max !best 2
  end

let%expect_test "a zero coupon bond discounts" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 100 } in
  let p = price m (Products.zcb ~date:horizon ~amount:100.0) in
  Printf.printf "%.4f" p;
  [%expect {| 95.1229 |}]

let%expect_test "the European call converges to Black-Scholes" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let at steps =
    let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps } in
    price m (Products.european_call ~strike:100.0 ~expiry:horizon)
  in
  Printf.printf "%b %b"
    (Float.abs (at 200 -. bs) < 0.05)
    (Float.abs (((at 2000 +. at 2001) /. 2.0) -. bs) < 0.01);
  [%expect {| true true |}]

let%expect_test "averaging two adjacent step counts removes the oscillation" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let at steps =
    let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps } in
    price m (Products.european_call ~strike:100.0 ~expiry:horizon)
  in
  let single = Float.abs (at 501 -. bs) in
  let averaged = Float.abs (((at 500 +. at 501) /. 2.0) -. bs) in
  Printf.printf "%b" (averaged < single);
  [%expect {| true |}]

let%expect_test "the digital matches its closed form" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 2000 } in
  let lattice =
    price m (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0)
  in
  let closed =
    Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0
  in
  Printf.printf "%b" (Float.abs (lattice -. closed) < 0.02);
  [%expect {| true |}]

let%expect_test "give negates and and adds" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 50 } in
  let b = Products.zcb ~date:horizon ~amount:100.0 in
  Printf.printf "%.8f" (price m (Contract.And (b, Contract.Give b)));
  [%expect {| 0.00000000 |}]
