open Contract_lab

let today = Date.of_ymd 2026 1 1
let horizon = Date.of_ymd 2027 1 1

let mc ?(paths = 40_000) ?(steps = 50) ?(seed = 5) () =
  { Mc.s0 = 36.0; r = 0.06; sigma = 0.2; today; horizon; steps; paths; seed }

let lattice steps =
  { Lattice.s0 = 36.0; r = 0.06; sigma = 0.2; today; horizon; steps }

let american_put = Products.american_put ~strike:40.0
let european_put = Products.european_put ~strike:40.0 ~expiry:horizon

let test_monte_carlo_still_refuses_what_it_cannot_price () =
  Alcotest.check_raises "anytime is refused by plain Monte Carlo"
    (Mc.Unsupported "contract contains a holder choice") (fun () ->
      ignore (Mc.price (mc ~paths:100 ()) american_put))

let test_lsm_agrees_with_the_lattice_on_the_american_put () =
  let price, se = Lsm.price (mc ()) american_put ~strike:40.0 in
  let reference = Lattice.price (lattice 2000) american_put in
  (* Longstaff-Schwartz is biased low: the exercise rule is fitted on the same
     paths it is applied to. It should land under the lattice, and close. *)
  Alcotest.(check bool)
    "within 3% of the lattice" true
    (Float.abs (price -. reference) /. reference < 0.03);
  Alcotest.(check bool)
    "biased low, as the method is" true
    (price < reference +. (3.0 *. se));
  Alcotest.(check bool) "standard error is small" true (se < 0.05)

let test_the_early_exercise_premium_is_not_negative () =
  let american, _ = Lsm.price (mc ()) american_put ~strike:40.0 in
  let european, _ = Mc.price (mc ()) european_put in
  Alcotest.(check bool)
    "american at least european" true
    (american > european -. 0.01);
  Alcotest.(check bool)
    "and strictly more, at this strike" true
    (american > european +. 0.2)

let test_an_american_call_without_dividends_is_never_exercised_early () =
  let call =
    Contract.Anytime
      ( Obs.Always,
        Contract.Scale
          ( Obs.Max (Obs.Sub (Obs.Spot, Obs.Konst 40.0), Obs.Konst 0.0),
            Contract.One ) )
  in
  let american, se = Lsm.price (mc ()) call ~strike:40.0 in
  let european, se_e =
    Mc.price (mc ()) (Products.european_call ~strike:40.0 ~expiry:horizon)
  in
  let tol = 3.0 *. sqrt ((se *. se) +. (se_e *. se_e)) in
  Alcotest.(check bool)
    "no early exercise value" true
    (Float.abs (american -. european) < Float.max tol 0.01)

let test_the_same_seed_gives_the_same_price () =
  let a, _ = Lsm.price (mc ~paths:2_000 ()) american_put ~strike:40.0 in
  let b, _ = Lsm.price (mc ~paths:2_000 ()) american_put ~strike:40.0 in
  Alcotest.(check (float 1e-12)) "deterministic" a b

let test_more_exercise_dates_are_worth_more () =
  (* A holder who may exercise at more dates cannot be worse off. With few
     steps the difference is real; with many it flattens out. *)
  let coarse, _ = Lsm.price (mc ~steps:5 ()) american_put ~strike:40.0 in
  let fine, _ = Lsm.price (mc ~steps:50 ()) american_put ~strike:40.0 in
  Alcotest.(check bool) "more dates, more value" true (fine > coarse -. 0.02)

let suite =
  [
    Alcotest.test_case "plain mc refuses" `Quick
      test_monte_carlo_still_refuses_what_it_cannot_price;
    Alcotest.test_case "lsm against the lattice" `Quick
      test_lsm_agrees_with_the_lattice_on_the_american_put;
    Alcotest.test_case "early exercise premium" `Quick
      test_the_early_exercise_premium_is_not_negative;
    Alcotest.test_case "american call, no dividends" `Quick
      test_an_american_call_without_dividends_is_never_exercised_early;
    Alcotest.test_case "deterministic" `Quick
      test_the_same_seed_gives_the_same_price;
    Alcotest.test_case "more dates are worth more" `Quick
      test_more_exercise_dates_are_worth_more;
  ]
