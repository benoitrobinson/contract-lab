open Contract_lab

let expiry = Date.of_ymd 2027 1 1

(* --json is for vol-lab's panel, which draws these numbers rather than parsing
   the text tables. Every value is computed once and printed either way. *)
let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Printf.bprintf b "\\u%04x" (Char.code c)
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_float x =
  if Float.is_finite x then Printf.sprintf "%.10g" x else "null"

let json_list items = "[" ^ String.concat ", " items ^ "]"

let json_object fields =
  "{"
  ^ String.concat ", "
      (List.map (fun (k, v) -> json_string k ^ ": " ^ v) fields)
  ^ "}"

let termsheet json =
  let products =
    [
      ("zero coupon bond", Products.zcb ~date:expiry ~amount:100.0);
      ("european call", Products.european_call ~strike:100.0 ~expiry);
      ("digital call", Products.digital_call ~strike:100.0 ~expiry ~cash:1.0);
      ( "down and out call",
        Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry );
      ("american put", Products.american_put ~strike:100.0);
      ( "autocallable",
        Products.autocallable
          ~observations:
            [
              Date.of_ymd 2026 12 25;
              Date.of_ymd 2027 3 25;
              Date.of_ymd 2027 6 25;
            ]
          ~trigger:100.0 ~coupon:5.0 ~notional:100.0 ~ki_barrier:60.0 );
    ]
  in
  if json then
    print_endline
      (json_list
         (List.map
            (fun (name, c) ->
              json_object
                [
                  ("name", json_string name);
                  ("contract", json_string (Contract.to_string c));
                ])
            products))
  else
    List.iter
      (fun (name, c) -> Printf.printf "%-22s %s\n" name (Contract.to_string c))
      products

let study json path =
  let sl = Svi.of_file path in
  (* Strikes are fractions of the forward, so the table means the same thing
     whatever the underlying is worth. *)
  let moneyness = [ 0.80; 0.90; 0.95; 1.00; 1.05; 1.10; 1.20 ] in
  let strikes = List.map (fun m -> m *. sl.Svi.forward) moneyness in
  let atm = Svi.sigma sl ~strike:sl.Svi.forward in
  let rows = Study.table sl ~s:sl.Svi.forward ~r:0.0 ~strikes in
  if json then
    print_endline
      (json_object
         [
           ("slice", json_string path);
           ("forward", json_float sl.Svi.forward);
           ("expiry_years", json_float sl.Svi.t);
           ("atm_vol", json_float atm);
           ( "rows",
             json_list
               (List.map2
                  (fun m (k, flat, spread, bps) ->
                    json_object
                      [
                        ("moneyness", json_float m);
                        ("strike", json_float k);
                        ("n_d2", json_float flat);
                        ("call_spread", json_float spread);
                        ("difference_bps", json_float bps);
                      ])
                  moneyness rows) );
         ])
  else begin
    Printf.printf "forward %.2f   expiry %.4f years   atm implied vol %.2f%%\n"
      sl.Svi.forward sl.Svi.t (100.0 *. atm);
    Printf.printf
      "\nK/F     strike       N(d2)     call spread   difference (bps)\n";
    List.iter2
      (fun m (k, flat, spread, bps) ->
        Printf.printf "%-7.2f %-12.1f %-9.5f %-13.5f %+.1f\n" m k flat spread
          bps)
      moneyness rows
  end

(* Every number the README quotes is printed here, so a reader can regenerate
   the table rather than trust it. The tests assert the identities; this prints
   what they were worth when they passed. *)
let checks json =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let model ?(s0 = 100.0) ?(r = 0.05) steps =
    { Lattice.s0; r; sigma = 0.2; today; horizon; steps }
  in
  let call = Products.european_call ~strike:100.0 ~expiry:horizon in
  let steps =
    Lattice.boyle_lau_steps ~s:100.0 ~h:90.0 ~sigma:0.2 ~t:1.0 ~max_steps:3000
  in
  let put_model steps =
    { Lattice.s0 = 36.0; r = 0.06; sigma = 0.2; today; horizon; steps }
  in
  let american = Products.american_put ~strike:40.0 in
  let european = Products.european_put ~strike:40.0 ~expiry:horizon in
  let lsm, se =
    Lsm.price
      {
        Mc.s0 = 36.0;
        r = 0.06;
        sigma = 0.2;
        today;
        horizon;
        steps = 50;
        paths = 40_000;
        seed = 5;
      }
      american ~strike:40.0
  in
  (* (label, value, decimals, standard error) *)
  let rows =
    [
      ( "black-scholes call",
        Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0,
        4,
        None );
      ("lattice call, 200 steps", Lattice.price (model 200) call, 4, None);
      ("lattice call, 2000 steps", Lattice.price (model 2000) call, 4, None);
      ( "lattice call, 2000 and 2001 averaged",
        (Lattice.price (model 2000) call +. Lattice.price (model 2001) call)
        /. 2.0,
        4,
        None );
      ( "digital, closed form",
        Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0,
        6,
        None );
      ( "digital, lattice at 2000 steps",
        Lattice.price (model 2000)
          (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0),
        6,
        None );
      ("knock-out, Boyle-Lau steps", float_of_int steps, 0, None);
      ( "knock-out, lattice",
        Lattice.price (model steps)
          (Products.down_and_out_call ~strike:100.0 ~barrier:90.0
             ~expiry:horizon),
        4,
        None );
      ( "knock-out, Reiner-Rubinstein",
        Bs.down_and_out_call ~s:100.0 ~k:100.0 ~h:90.0 ~r:0.05 ~sigma:0.2 ~t:1.0,
        4,
        None );
      ( "american put, 500 steps",
        Lattice.price (put_model 500) american,
        4,
        None );
      ( "american put, 2000 steps",
        Lattice.price (put_model 2000) american,
        4,
        None );
      ( "european put, 500 steps",
        Lattice.price (put_model 500) european,
        4,
        None );
      ( "early exercise premium",
        Lattice.price (put_model 500) american
        -. Lattice.price (put_model 500) european,
        4,
        None );
      ("american put, Longstaff-Schwartz", lsm, 4, Some se);
    ]
  in
  if json then
    print_endline
      (json_list
         (List.map
            (fun (label, v, _, se) ->
              json_object
                [
                  ("label", json_string label);
                  ("value", json_float v);
                  ("se", match se with Some e -> json_float e | None -> "null");
                ])
            rows))
  else
    List.iter
      (fun (label, v, d, se) ->
        let value =
          match se with
          | Some e -> Printf.sprintf "%.*f +/- %.*f" d v d e
          | None -> Printf.sprintf "%.*f" d v
        in
        Printf.printf "%-41s %s\n" label value)
      rows

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let json = List.mem "--json" args in
  match List.filter (( <> ) "--json") args with
  | [ "termsheet" ] -> termsheet json
  | [ "checks" ] -> checks json
  | [ "study" ] -> study json "data/svi_slice.txt"
  | [ "study"; path ] -> study json path
  | _ ->
      print_endline
        "usage: main (termsheet | checks | study [slice-file]) [--json]"
