let m steps =
  {
    Contract_lab.Lattice.s0 = 36.0;
    r = 0.06;
    sigma = 0.2;
    today = Contract_lab.Date.of_ymd 2026 1 1;
    horizon = Contract_lab.Date.of_ymd 2027 1 1;
    steps;
  }

let price steps c = Contract_lab.Lattice.price (m steps) c
let expiry = Contract_lab.Date.of_ymd 2027 1 1

let test_american_call_equals_european () =
  (* With no dividends it is never optimal to exercise a call early. On the same
     tree the two prices are identical, not merely close. *)
  let american =
    Contract_lab.Contract.Anytime
      ( Contract_lab.Obs.Always,
        Contract_lab.Contract.Scale
          ( Contract_lab.Obs.Max
              ( Contract_lab.Obs.Sub
                  (Contract_lab.Obs.Spot, Contract_lab.Obs.Konst 40.0),
                Contract_lab.Obs.Konst 0.0 ),
            Contract_lab.Contract.One ) )
  in
  let european = Contract_lab.Products.european_call ~strike:40.0 ~expiry in
  Alcotest.(check (float 1e-9))
    "american call = european" (price 500 european) (price 500 american)

let test_early_exercise_premium_is_positive () =
  let american = Contract_lab.Products.american_put ~strike:40.0 in
  let european = Contract_lab.Products.european_put ~strike:40.0 ~expiry in
  let premium = price 500 american -. price 500 european in
  Alcotest.(check bool) "premium positive" true (premium > 0.01)

let test_american_put_converges () =
  let american = Contract_lab.Products.american_put ~strike:40.0 in
  let a = price 500 american and b = price 2000 american in
  Alcotest.(check bool) "converged" true (Float.abs (a -. b) < 0.01);
  (* Sanity: deep in the money at S=36, K=40, the put is worth at least its
     intrinsic value of 4. *)
  Alcotest.(check bool) "at least intrinsic" true (b >= 4.0)

let suite =
  [
    Alcotest.test_case "american call = european" `Quick
      test_american_call_equals_european;
    Alcotest.test_case "early exercise premium" `Quick
      test_early_exercise_premium_is_positive;
    Alcotest.test_case "american put converges" `Quick
      test_american_put_converges;
  ]
