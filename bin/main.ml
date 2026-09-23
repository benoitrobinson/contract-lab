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
            [ Date.of_ymd 2026 12 25; Date.of_ymd 2027 3 25; Date.of_ymd 2027 6 25 ]
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

let () =
  match Sys.argv with
  | [| _; "termsheet" |] -> termsheet ()
  | [| _; "study" |] -> study "data/svi_slice.txt"
  | [| _; "study"; path |] -> study path
  | _ -> print_endline "usage: main (termsheet | study [slice-file])"
