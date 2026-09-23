open Contract_lab

let expiry = Date.of_ymd 2027 1 1

let termsheet () =
  List.iter
    (fun (name, c) -> Printf.printf "%-22s %s\n" name (Contract.to_string c))
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

let study path =
  let sl = Svi.of_file path in
  Printf.printf "strike   N(d2)     call spread   difference (bps)\n";
  List.iter
    (fun (k, flat, spread, bps) ->
      Printf.printf "%-8.1f %-9.5f %-13.5f %+.1f\n" k flat spread bps)
    (Study.table sl ~s:sl.Svi.forward ~r:0.0
       ~strikes:[ 80.0; 90.0; 95.0; 100.0; 105.0; 110.0; 120.0 ])

(* Every number the README quotes is printed here, so a reader can regenerate
   the table rather than trust it. The tests assert the identities; this prints
   what they were worth when they passed. *)
let checks () =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let model ?(s0 = 100.0) ?(r = 0.05) steps =
    { Lattice.s0; r; sigma = 0.2; today; horizon; steps }
  in
  let call = Products.european_call ~strike:100.0 ~expiry:horizon in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "black-scholes call                        %.4f\n" bs;
  Printf.printf "lattice call, 200 steps                   %.4f\n"
    (Lattice.price (model 200) call);
  Printf.printf "lattice call, 2000 steps                  %.4f\n"
    (Lattice.price (model 2000) call);
  Printf.printf "lattice call, 2000 and 2001 averaged      %.4f\n"
    ((Lattice.price (model 2000) call +. Lattice.price (model 2001) call) /. 2.0);
  Printf.printf "digital, closed form                      %.6f\n"
    (Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0);
  Printf.printf "digital, lattice at 2000 steps            %.6f\n"
    (Lattice.price (model 2000)
       (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0));
  let steps =
    Lattice.boyle_lau_steps ~s:100.0 ~h:90.0 ~sigma:0.2 ~t:1.0 ~max_steps:3000
  in
  Printf.printf "knock-out, Boyle-Lau steps                %d\n" steps;
  Printf.printf "knock-out, lattice                        %.4f\n"
    (Lattice.price (model steps)
       (Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry:horizon));
  Printf.printf "knock-out, Reiner-Rubinstein              %.4f\n"
    (Bs.down_and_out_call ~s:100.0 ~k:100.0 ~h:90.0 ~r:0.05 ~sigma:0.2 ~t:1.0);
  let put_model steps =
    { Lattice.s0 = 36.0; r = 0.06; sigma = 0.2; today; horizon; steps }
  in
  let american = Products.american_put ~strike:40.0 in
  let european = Products.european_put ~strike:40.0 ~expiry:horizon in
  Printf.printf "american put, 500 steps                   %.4f\n"
    (Lattice.price (put_model 500) american);
  Printf.printf "american put, 2000 steps                  %.4f\n"
    (Lattice.price (put_model 2000) american);
  Printf.printf "european put, 500 steps                   %.4f\n"
    (Lattice.price (put_model 500) european);
  Printf.printf "early exercise premium                    %.4f\n"
    (Lattice.price (put_model 500) american -. Lattice.price (put_model 500) european)

let () =
  match Sys.argv with
  | [| _; "termsheet" |] -> termsheet ()
  | [| _; "checks" |] -> checks ()
  | [| _; "study" |] -> study "data/svi_slice.txt"
  | [| _; "study"; path |] -> study path
  | _ -> print_endline "usage: main (termsheet | checks | study [slice-file])"
