open Contract_lab

let today = Date.of_ymd 2026 1 1
let horizon = Date.of_ymd 2027 1 1

let model =
  { Lattice.s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 60 }

let float_obs =
  let open QCheck.Gen in
  sized_size (int_range 0 2)
  @@ fix (fun self n ->
      match n with
      | 0 ->
          oneof
            [
              map (fun k -> Obs.Konst (float_of_int k)) (int_range 50 150);
              return Obs.Spot;
            ]
      | n ->
          oneof
            [
              map2 (fun a b -> Obs.Sub (a, b)) (self (n - 1)) (self (n - 1));
              map2 (fun a b -> Obs.Max (a, b)) (self (n - 1)) (self (n - 1));
              map (fun k -> Obs.Konst (float_of_int k)) (int_range 0 2);
            ])

let bool_obs =
  let open QCheck.Gen in
  oneof
    [
      return Obs.Always;
      map
        (fun k -> Obs.Ge (Obs.Spot, Obs.Konst (float_of_int k)))
        (int_range 60 140);
      map
        (fun k -> Obs.Le (Obs.Spot, Obs.Konst (float_of_int k)))
        (int_range 60 140);
      map
        (fun d -> Obs.AtOrAfter (Date.add_days today (d * 30)))
        (int_range 1 12);
    ]

(* No Or and no Anytime: the property compares both interpreters, and Monte
   Carlo cannot price a holder choice. Those rules are covered by unit tests. *)
let contract =
  let open QCheck.Gen in
  sized_size (int_range 0 3)
  @@ fix (fun self n ->
      match n with
      | 0 -> oneof [ return Contract.Zero; return Contract.One ]
      | n ->
          oneof
            [
              map (fun c -> Contract.Give c) (self (n - 1));
              map2
                (fun a b -> Contract.And (a, b))
                (self (n - 1))
                (self (n - 1));
              map2 (fun o c -> Contract.Scale (o, c)) float_obs (self (n - 1));
              map3
                (fun o a b -> Contract.Cond (o, a, b))
                bool_obs
                (self (n - 1))
                (self (n - 1));
              map2 (fun o c -> Contract.When (o, c)) bool_obs (self (n - 1));
              map2 (fun o c -> Contract.Until (o, c)) bool_obs (self (n - 1));
            ])

let arbitrary_contract = QCheck.make contract ~print:Contract.to_string

let prop_price_preserved =
  QCheck.Test.make ~name:"simplify preserves the lattice price" ~count:300
    arbitrary_contract (fun c ->
      let before = Lattice.price model c in
      let after = Lattice.price model (Simplify.simplify c) in
      Float.abs (before -. after) <= 1e-9 *. (1.0 +. Float.abs before))

let prop_simplify_is_idempotent =
  QCheck.Test.make ~name:"simplify is idempotent" ~count:300 arbitrary_contract
    (fun c ->
      let once = Simplify.simplify c in
      Simplify.simplify once = once)

let suite =
  List.map QCheck_alcotest.to_alcotest
    [ prop_price_preserved; prop_simplify_is_idempotent ]
