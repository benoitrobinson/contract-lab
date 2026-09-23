(** A raw SVI slice: total variance w(k) = a + b (rho (k - m) + sqrt((k - m)^2 +
    s^2)) in log-moneyness k = ln(K / F), for one expiry. *)
type slice = {
  a : float;
  b : float;
  rho : float;
  m : float;
  s : float;
  t : float;
  forward : float;
}

let total_variance sl k =
  sl.a
  +. sl.b
     *. ((sl.rho *. (k -. sl.m)) +. sqrt (((k -. sl.m) ** 2.0) +. (sl.s ** 2.0)))

let sigma sl ~strike =
  let k = log (strike /. sl.forward) in
  sqrt (Float.max 1e-12 (total_variance sl k) /. sl.t)

(** dsigma/dK by central difference, one percent of the strike either side. *)
let skew sl ~strike =
  let h = 0.01 *. strike in
  (sigma sl ~strike:(strike +. h) -. sigma sl ~strike:(strike -. h)) /. (2.0 *. h)

let of_file path =
  (* Lines that are not "key value" are skipped, so the file can carry the
     header comment that records which vol-lab run produced it. *)
  let get key line =
    match Scanf.sscanf_opt line " %s %f" (fun k v -> (k, v)) with
    | Some (k, v) when k = key -> Some v
    | _ -> None
  in
  let lines = In_channel.with_open_text path In_channel.input_lines in
  let find key =
    match List.filter_map (get key) lines with
    | v :: _ -> v
    | [] -> failwith (Printf.sprintf "%s: missing key %s" path key)
  in
  {
    a = find "a";
    b = find "b";
    rho = find "rho";
    m = find "m";
    s = find "s";
    t = find "t";
    forward = find "forward";
  }
