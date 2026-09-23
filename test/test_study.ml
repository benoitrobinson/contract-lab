open Contract_lab

let flat =
  {
    Svi.a = 0.04;
    b = 0.0;
    rho = 0.0;
    m = 0.0;
    s = 0.1;
    t = 1.0;
    forward = 100.0;
  }

let skewed = { flat with Svi.b = 0.1; rho = -0.3 }

let test_flat_slice_has_no_skew () =
  Alcotest.(check (float 1e-9))
    "sigma is flat"
    (Svi.sigma flat ~strike:80.0)
    (Svi.sigma flat ~strike:120.0);
  Alcotest.(check (float 1e-6)) "skew is zero" 0.0 (Svi.skew flat ~strike:100.0)

let test_flat_slice_recovers_n_d2 () =
  let s = 100.0 and r = 0.0 in
  let spread = Study.digital_from_spread flat ~s ~r ~strike:100.0 in
  let closed = Study.digital_flat flat ~s ~r ~strike:100.0 in
  Alcotest.(check (float 1e-4)) "call spread equals N(d2)" closed spread

let test_the_skew_term_explains_the_difference () =
  let s = 100.0 and r = 0.0 in
  let strike = 95.0 in
  let spread = Study.digital_from_spread skewed ~s ~r ~strike in
  let closed = Study.digital_flat skewed ~s ~r ~strike in
  let adjustment = Study.skew_adjustment skewed ~s ~r ~strike in
  (* digital = N(d2) - vega * dsigma/dK, to the accuracy of the finite difference *)
  Alcotest.(check (float 1e-3))
    "decomposition holds" (closed -. adjustment) spread;
  Alcotest.(check bool)
    "and it is not negligible" true
    (Float.abs (spread -. closed) > 1e-3)

let test_the_dsl_prices_the_same_digital () =
  let s = 100.0 and r = 0.0 in
  let strike = 95.0 in
  let expiry =
    Date.add_days (Date.of_ymd 2026 1 1) (int_of_float (skewed.Svi.t *. 365.0))
  in
  let m =
    {
      Lattice.s0 = s;
      r;
      sigma = Svi.sigma skewed ~strike;
      today = Date.of_ymd 2026 1 1;
      horizon = expiry;
      steps = 2000;
    }
  in
  let dsl = Lattice.price m (Products.digital_call ~strike ~expiry ~cash:1.0) in
  let closed = Study.digital_flat skewed ~s ~r ~strike in
  Alcotest.(check bool)
    "lattice agrees with the flat-vol closed form" true
    (Float.abs (dsl -. closed) < 0.02)

let suite =
  [
    Alcotest.test_case "flat slice" `Quick test_flat_slice_has_no_skew;
    Alcotest.test_case "flat recovers N(d2)" `Quick
      test_flat_slice_recovers_n_d2;
    Alcotest.test_case "skew term" `Quick
      test_the_skew_term_explains_the_difference;
    Alcotest.test_case "dsl digital" `Quick test_the_dsl_prices_the_same_digital;
  ]
