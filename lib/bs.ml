(* Abramowitz and Stegun 26.2.17, absolute error below 7.5e-8. Written here so a
   clone reproduces every number without a numerical dependency. *)
let norm_cdf x =
  let b1 = 0.319381530
  and b2 = -0.356563782
  and b3 = 1.781477937
  and b4 = -1.821255978
  and b5 = 1.330274429
  and p = 0.2316419 in
  let ax = Float.abs x in
  let k = 1.0 /. (1.0 +. (p *. ax)) in
  let poly =
    ((((((((b5 *. k) +. b4) *. k) +. b3) *. k) +. b2) *. k) +. b1) *. k
  in
  let phi = exp (-0.5 *. ax *. ax) /. sqrt (2.0 *. Float.pi) in
  let upper_tail = phi *. poly in
  if x >= 0.0 then 1.0 -. upper_tail else upper_tail

let d1 ~s ~k ~r ~sigma ~t =
  (log (s /. k) +. ((r +. (0.5 *. sigma *. sigma)) *. t)) /. (sigma *. sqrt t)

let d2 ~s ~k ~r ~sigma ~t = d1 ~s ~k ~r ~sigma ~t -. (sigma *. sqrt t)

let call ~s ~k ~r ~sigma ~t =
  if t <= 0.0 then Float.max (s -. k) 0.0
  else
    (s *. norm_cdf (d1 ~s ~k ~r ~sigma ~t))
    -. (k *. exp (-.r *. t) *. norm_cdf (d2 ~s ~k ~r ~sigma ~t))

let put ~s ~k ~r ~sigma ~t =
  if t <= 0.0 then Float.max (k -. s) 0.0
  else
    (k *. exp (-.r *. t) *. norm_cdf (-.d2 ~s ~k ~r ~sigma ~t))
    -. (s *. norm_cdf (-.d1 ~s ~k ~r ~sigma ~t))

let vega ~s ~k ~r ~sigma ~t =
  let d = d1 ~s ~k ~r ~sigma ~t in
  s *. sqrt t *. exp (-0.5 *. d *. d) /. sqrt (2.0 *. Float.pi)

let digital_call ~s ~k ~r ~sigma ~t ~cash =
  cash *. exp (-.r *. t) *. norm_cdf (d2 ~s ~k ~r ~sigma ~t)

(* Reiner and Rubinstein (1991), down-and-out call with the strike above the
   barrier, no rebate, no dividends: c = A - C in Haug's decomposition. *)
let down_and_out_call ~s ~k ~h ~r ~sigma ~t =
  let sqrt_t = sqrt t in
  let mu = (r -. (0.5 *. sigma *. sigma)) /. (sigma *. sigma) in
  let x1 =
    (log (s /. k) /. (sigma *. sqrt_t)) +. ((1.0 +. mu) *. sigma *. sqrt_t)
  in
  let y1 =
    (log (h *. h /. (s *. k)) /. (sigma *. sqrt_t))
    +. ((1.0 +. mu) *. sigma *. sqrt_t)
  in
  let a =
    (s *. norm_cdf x1)
    -. (k *. exp (-.r *. t) *. norm_cdf (x1 -. (sigma *. sqrt_t)))
  in
  let c =
    (s *. ((h /. s) ** (2.0 *. (mu +. 1.0))) *. norm_cdf y1)
    -. k
       *. exp (-.r *. t)
       *. ((h /. s) ** (2.0 *. mu))
       *. norm_cdf (y1 -. (sigma *. sqrt_t))
  in
  Float.max (a -. c) 0.0

let%expect_test "the normal cdf is symmetric and anchored" =
  Printf.printf "%.6f %.6f %.6f" (norm_cdf 0.0) (norm_cdf 1.96)
    (norm_cdf (-1.96));
  [%expect {| 0.500000 0.975002 0.024998 |}]

let%expect_test "the textbook call value" =
  Printf.printf "%.4f" (call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0);
  [%expect {| 10.4506 |}]

let%expect_test "put-call parity holds" =
  let c = call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let p = put ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%.10f" (c -. p -. (100.0 -. (100.0 *. exp (-0.05))));
  [%expect {| 0.0000000000 |}]

let%expect_test
    "a digital is the discounted probability of finishing in the money" =
  let d = digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0 in
  Printf.printf "%.6f" d;
  [%expect {| 0.532325 |}]

let%expect_test "a barrier at zero is just a call" =
  let c = call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let b =
    down_and_out_call ~s:100.0 ~k:100.0 ~h:1e-8 ~r:0.05 ~sigma:0.2 ~t:1.0
  in
  Printf.printf "%.8f" (c -. b);
  [%expect {| 0.00000000 |}]

let%expect_test "a barrier just under spot is nearly worthless" =
  let b =
    down_and_out_call ~s:100.0 ~k:100.0 ~h:99.99 ~r:0.05 ~sigma:0.2 ~t:1.0
  in
  Printf.printf "%b" (b < 0.05);
  [%expect {| true |}]
