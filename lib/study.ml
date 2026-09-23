(** The digital as the market would price it if one volatility applied: the
    Black-Scholes cash-or-nothing value at sigma(K). *)
let digital_flat sl ~s ~r ~strike =
  Bs.digital_call ~s ~k:strike ~r ~sigma:(Svi.sigma sl ~strike) ~t:sl.Svi.t
    ~cash:1.0

(** The digital as a call spread on the smile: each leg priced at its own
    implied volatility. *)
let digital_from_spread sl ~s ~r ~strike =
  let h = 0.005 *. strike in
  let c k = Bs.call ~s ~k ~r ~sigma:(Svi.sigma sl ~strike:k) ~t:sl.Svi.t in
  -.(c (strike +. h) -. c (strike -. h)) /. (2.0 *. h)

(** vega * dsigma/dK: the term that separates the two, positive when the smile
    slopes up, which makes the digital cheaper than N(d2) says. *)
let skew_adjustment sl ~s ~r ~strike =
  let sigma = Svi.sigma sl ~strike in
  Bs.vega ~s ~k:strike ~r ~sigma ~t:sl.Svi.t *. Svi.skew sl ~strike

let table sl ~s ~r ~strikes =
  List.map
    (fun strike ->
      let flat = digital_flat sl ~s ~r ~strike in
      let spread = digital_from_spread sl ~s ~r ~strike in
      (strike, flat, spread, (spread -. flat) *. 10_000.0))
    strikes
