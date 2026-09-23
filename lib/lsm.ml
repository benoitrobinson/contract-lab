(** Least-squares Monte Carlo, after Longstaff and Schwartz (2001).

    [Mc] refuses any contract containing a holder's choice, because a forward
    simulation cannot see the optimal decision: at a node you know the payoff
    from exercising, and the value of waiting is an expectation over paths that
    have not happened yet. Longstaff and Schwartz answer that by estimating the
    continuation value from the cross-section of paths, regressing the realised
    discounted future cashflow on functions of the state, and exercising when
    the immediate payoff beats the fitted continuation.

    The estimator is biased low by construction: the exercise rule is fitted on
    the same paths it is applied to, and a rule chosen with hindsight on a
    finite sample cannot beat the true optimal rule out of sample. The tests
    hold it against the lattice for that reason, with a tolerance rather than an
    equality.

    What is supported is [Anytime (o, c)] where [c] itself is choice-free, which
    covers American options and is the case the paper treats. A nested choice
    would need a nested regression, and refusing it is better than pricing it
    wrongly. *)

type basis = { one : float; s : float; s2 : float }

let basis_of spot strike =
  (* Scaled by the strike so the normal equations stay well conditioned when
     spot is 40 or 40,000. *)
  let x = spot /. strike in
  { one = 1.0; s = x; s2 = x *. x }

(** Solves the 3x3 normal equations by Gaussian elimination with partial
    pivoting. A singular system means the in-the-money paths carried no
    information, and the caller falls back to never exercising early. *)
let solve3 (a : float array array) (b : float array) =
  let a = Array.map Array.copy a and b = Array.copy b in
  let n = 3 in
  try
    for col = 0 to n - 1 do
      let pivot = ref col in
      for row = col + 1 to n - 1 do
        if Float.abs a.(row).(col) > Float.abs a.(!pivot).(col) then
          pivot := row
      done;
      if Float.abs a.(!pivot).(col) < 1e-12 then raise Exit;
      if !pivot <> col then begin
        let tmp = a.(col) in
        a.(col) <- a.(!pivot);
        a.(!pivot) <- tmp;
        let tmp = b.(col) in
        b.(col) <- b.(!pivot);
        b.(!pivot) <- tmp
      end;
      for row = col + 1 to n - 1 do
        let f = a.(row).(col) /. a.(col).(col) in
        for k = col to n - 1 do
          a.(row).(k) <- a.(row).(k) -. (f *. a.(col).(k))
        done;
        b.(row) <- b.(row) -. (f *. b.(col))
      done
    done;
    let x = Array.make n 0.0 in
    for row = n - 1 downto 0 do
      let acc = ref b.(row) in
      for k = row + 1 to n - 1 do
        acc := !acc -. (a.(row).(k) *. x.(k))
      done;
      x.(row) <- !acc /. a.(row).(row)
    done;
    Some x
  with Exit -> None

let regress (points : (basis * float) list) =
  let a = Array.make_matrix 3 3 0.0 and b = Array.make 3 0.0 in
  List.iter
    (fun (p, y) ->
      let v = [| p.one; p.s; p.s2 |] in
      for i = 0 to 2 do
        for j = 0 to 2 do
          a.(i).(j) <- a.(i).(j) +. (v.(i) *. v.(j))
        done;
        b.(i) <- b.(i) +. (v.(i) *. y)
      done)
    points;
  solve3 a b

let evaluate coeffs p =
  match coeffs with
  | None -> 0.0
  | Some c -> (c.(0) *. p.one) +. (c.(1) *. p.s) +. (c.(2) *. p.s2)

(** [price m contract ~strike] where [strike] only scales the regression basis.
    Pass the contract's own strike when it has one; any positive number of the
    right order of magnitude works. *)
let price (m : Mc.model) (c : Contract.t) ~strike =
  let o, inner =
    match c with
    | Contract.Anytime (o, inner) when not (Mc.has_choice inner) -> (o, inner)
    | _ ->
        raise (Mc.Unsupported "lsm prices anytime over a choice-free contract")
  in
  let rng = Random.State.make [| m.Mc.seed |] in
  let paths = Array.init m.Mc.paths (fun _ -> Mc.simulate m rng) in
  let n = m.Mc.steps in
  let dt = Mc.dt m in
  let disc = exp (-.m.Mc.r *. dt) in

  (* For each path: the step at which the holder currently plans to exercise,
     and the value taken there, discounted to that step. *)
  let stop_step = Array.make m.Mc.paths n in
  let stop_value =
    Array.map
      (fun path ->
        let st = Mc.state m path n in
        if Obs.eval o st then Mc.pv m path ~limit:n n inner else 0.0)
      paths
  in

  for i = n - 1 downto 1 do
    (* Discounted value of continuing, as realised on each path. *)
    let continuation =
      Array.mapi
        (fun k _ ->
          stop_value.(k) *. (disc ** float_of_int (stop_step.(k) - i)))
        paths
    in
    let live =
      Array.to_list
        (Array.mapi
           (fun k path ->
             let st = Mc.state m path i in
             if not (Obs.eval o st) then None
             else
               let immediate = Mc.pv m path ~limit:n i inner in
               if immediate > 0.0 then Some (k, immediate, st.Obs.spot)
               else None)
           paths)
    in
    let live = List.filter_map Fun.id live in
    if live <> [] then begin
      let coeffs =
        regress
          (List.map
             (fun (k, _, spot) -> (basis_of spot strike, continuation.(k)))
             live)
      in
      List.iter
        (fun (k, immediate, spot) ->
          if immediate > evaluate coeffs (basis_of spot strike) then begin
            stop_step.(k) <- i;
            stop_value.(k) <- immediate
          end)
        live
    end
  done;

  let total =
    Array.to_list stop_value
    |> List.mapi (fun k v -> v *. (disc ** float_of_int stop_step.(k)))
    |> List.fold_left ( +. ) 0.0
  in
  let mean = total /. float_of_int m.Mc.paths in
  let var =
    Array.to_list stop_value
    |> List.mapi (fun k v ->
        let d = (v *. (disc ** float_of_int stop_step.(k))) -. mean in
        d *. d)
    |> List.fold_left ( +. ) 0.0
  in
  let se = sqrt (var /. float_of_int (m.Mc.paths * (m.Mc.paths - 1))) in
  (mean, se)
