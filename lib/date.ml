type t = int

let of_ymd y m d =
  let y = if m <= 2 then y - 1 else y in
  let era = (if y >= 0 then y else y - 399) / 400 in
  let yoe = y - (era * 400) in
  let mp = (m + 9) mod 12 in
  let doy = (((153 * mp) + 2) / 5) + d - 1 in
  let doe = (yoe * 365) + (yoe / 4) - (yoe / 100) + doy in
  (era * 146097) + doe - 719468

let to_ymd z =
  let z = z + 719468 in
  let era = (if z >= 0 then z else z - 146096) / 146097 in
  let doe = z - (era * 146097) in
  let yoe = (doe - (doe / 1460) + (doe / 36524) - (doe / 146096)) / 365 in
  let y = yoe + (era * 400) in
  let doy = doe - ((365 * yoe) + (yoe / 4) - (yoe / 100)) in
  let mp = ((5 * doy) + 2) / 153 in
  let d = doy - (((153 * mp) + 2) / 5) + 1 in
  let m = if mp < 10 then mp + 3 else mp - 9 in
  ((if m <= 2 then y + 1 else y), m, d)

let to_string t =
  let y, m, d = to_ymd t in
  Printf.sprintf "%04d-%02d-%02d" y m d

let add_days t n = t + n
let compare : t -> t -> int = Int.compare

(* ACT/365. A real system needs day-count conventions and a holiday calendar;
   this one says so in the README instead of pretending. *)
let year_fraction a b = float_of_int (b - a) /. 365.0

let%expect_test "epoch and a known date" =
  print_int (of_ymd 1970 1 1);
  [%expect {| 0 |}];
  print_int (of_ymd 2026 9 22);
  [%expect {| 20718 |}]

let%expect_test "round trips through the civil calendar" =
  let y, m, d = to_ymd (of_ymd 2028 2 29) in
  Printf.printf "%d-%02d-%02d" y m d;
  [%expect {| 2028-02-29 |}]

let%expect_test "a year is a year" =
  Printf.printf "%.6f" (year_fraction (of_ymd 2026 1 1) (of_ymd 2027 1 1));
  [%expect {| 1.000000 |}]
