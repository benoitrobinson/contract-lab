open Contract

let cash amount = Scale (Obs.Konst amount, One)
let zcb ~date ~amount = When (Obs.AtOrAfter date, cash amount)

let european_call ~strike ~expiry =
  When
    ( Obs.AtOrAfter expiry,
      Scale (Obs.Max (Obs.Sub (Obs.Spot, Obs.Konst strike), Obs.Konst 0.0), One)
    )

let european_put ~strike ~expiry =
  When
    ( Obs.AtOrAfter expiry,
      Scale (Obs.Max (Obs.Sub (Obs.Konst strike, Obs.Spot), Obs.Konst 0.0), One)
    )

let digital_call ~strike ~expiry ~cash:c =
  When
    ( Obs.AtOrAfter expiry,
      Cond (Obs.Ge (Obs.Spot, Obs.Konst strike), cash c, Zero) )

let down_and_out_call ~strike ~barrier ~expiry =
  Until (Obs.Le (Obs.Spot, Obs.Konst barrier), european_call ~strike ~expiry)

(* The holder may exercise at any node of the tree, whose horizon is the expiry,
   so the exercise window is `Always` rather than a date test. *)
let american_put ~strike =
  Anytime
    ( Obs.Always,
      Scale (Obs.Max (Obs.Sub (Obs.Konst strike, Obs.Spot), Obs.Konst 0.0), One)
    )

(* Pays a growing coupon plus notional on the first observation date where spot
   is at or above the trigger. If it never triggers, the holder is long the
   downside below the knock-in barrier at the last date. *)
let autocallable ~observations ~trigger ~coupon ~notional ~ki_barrier =
  let redeem n = cash (notional +. (coupon *. float_of_int n)) in
  let final =
    Cond
      ( Obs.Ge (Obs.Spot, Obs.Konst ki_barrier),
        cash notional,
        Scale (Obs.Mul (Obs.Konst (notional /. 100.0), Obs.Spot), One) )
  in
  let rec build n = function
    | [] -> Zero
    | [ last ] ->
        When
          ( Obs.AtOrAfter last,
            Cond (Obs.Ge (Obs.Spot, Obs.Konst trigger), redeem n, final) )
    | d :: rest ->
        When
          ( Obs.AtOrAfter d,
            Cond
              ( Obs.Ge (Obs.Spot, Obs.Konst trigger),
                redeem n,
                build (n + 1) rest ) )
  in
  build 1 observations

let%expect_test "a call prints as a term sheet" =
  print_string
    (Contract.to_string
       (european_call ~strike:100.0 ~expiry:(Date.of_ymd 2026 12 25)));
  [%expect {| when (on or after 2026-12-25) scale max(S - 100, 0) of one |}]

let%expect_test "a digital prints as a term sheet" =
  print_string
    (Contract.to_string
       (digital_call ~strike:100.0 ~expiry:(Date.of_ymd 2026 12 25) ~cash:1.0));
  [%expect
    {| when (on or after 2026-12-25) if (S >= 100) then scale 1 of one else zero |}]

let%expect_test "a knock-out wraps the contract it cancels" =
  print_string
    (Contract.to_string
       (down_and_out_call ~strike:100.0 ~barrier:80.0
          ~expiry:(Date.of_ymd 2026 12 25)));
  [%expect
    {| until (S <= 80) (when (on or after 2026-12-25) scale max(S - 100, 0) of one) |}]

let%expect_test "an autocallable is ten lines of algebra" =
  let d = Date.of_ymd in
  let c =
    autocallable
      ~observations:[ d 2026 12 25; d 2027 3 25; d 2027 6 25 ]
      ~trigger:100.0 ~coupon:5.0 ~notional:100.0 ~ki_barrier:60.0
  in
  print_string (String.sub (Contract.to_string c) 0 60);
  [%expect {| when (on or after 2026-12-25) if (S >= 100) then scale 105 o |}]
