let today = Contract_lab.Date.of_ymd 2026 1 1
let expiry = Contract_lab.Date.of_ymd 2027 1 1

let model steps =
  {
    Contract_lab.Lattice.s0 = 100.0;
    r = 0.05;
    sigma = 0.2;
    today;
    horizon = expiry;
    steps;
  }

let test_knock_out_matches_the_closed_form () =
  let steps =
    Contract_lab.Lattice.boyle_lau_steps ~s:100.0 ~h:90.0 ~sigma:0.2 ~t:1.0
      ~max_steps:3000
  in
  let lattice =
    Contract_lab.Lattice.price (model steps)
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:90.0
         ~expiry)
  in
  let closed =
    Contract_lab.Bs.down_and_out_call ~s:100.0 ~k:100.0 ~h:90.0 ~r:0.05
      ~sigma:0.2 ~t:1.0
  in
  (* Discrete monitoring on a tree prices a knock-out above continuous
     monitoring, so the lattice sits slightly above the closed form. *)
  Alcotest.(check bool)
    "within 3% of closed form" true
    (Float.abs (lattice -. closed) /. closed < 0.03);
  Alcotest.(check bool)
    "cheaper than the vanilla" true
    (lattice < Contract_lab.Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0)

let test_a_barrier_at_zero_is_the_vanilla () =
  let lattice =
    Contract_lab.Lattice.price (model 500)
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:1e-8
         ~expiry)
  in
  let vanilla =
    Contract_lab.Lattice.price (model 500)
      (Contract_lab.Products.european_call ~strike:100.0 ~expiry)
  in
  Alcotest.(check (float 1e-9)) "same as vanilla" vanilla lattice

let test_pointwise_absorption_is_not_a_knock_out () =
  let m = model 500 in
  let underlying = Contract_lab.Products.european_call ~strike:100.0 ~expiry in
  let cond =
    Contract_lab.Lattice.obs_process m
      (Contract_lab.Obs.Le (Contract_lab.Obs.Spot, Contract_lab.Obs.Konst 90.0))
  in
  let wrong =
    (Contract_lab.Lattice.absorb_pointwise cond
       (Contract_lab.Lattice.value m underlying)).(0).(0)
  in
  let right =
    Contract_lab.Lattice.price m
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:90.0
         ~expiry)
  in
  let vanilla = Contract_lab.Lattice.price m underlying in
  Alcotest.(check (float 1e-9))
    "pointwise returns the vanilla price" vanilla wrong;
  Alcotest.(check bool)
    "the real knock-out is worth less" true
    (right < vanilla -. 0.5)

let suite =
  [
    Alcotest.test_case "knock-out matches the closed form" `Quick
      test_knock_out_matches_the_closed_form;
    Alcotest.test_case "barrier at zero is the vanilla" `Quick
      test_a_barrier_at_zero_is_the_vanilla;
    Alcotest.test_case "pointwise absorption is not a knock-out" `Quick
      test_pointwise_absorption_is_not_a_knock_out;
  ]
