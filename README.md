# contract-lab

[![ci](https://github.com/benoitrobinson/contract-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/benoitrobinson/contract-lab/actions/workflows/ci.yml)

A derivative is not a product, it is an expression.

```ocaml
let down_and_out_call ~strike ~barrier ~expiry =
  Until (Le (Spot, Konst barrier), european_call ~strike ~expiry)
```

Ten combinators after Peyton Jones, Eber and Seward, observables typed by a GADT, and two
interpreters of the same algebra: a CRR lattice where `when`, `anytime` and `until` become
discounting, the Snell envelope and absorption, and a Monte Carlo that refuses any contract
containing a holder's choice instead of guessing at it.

```
$ dune exec bin/main.exe -- termsheet
zero coupon bond       when (on or after 2027-01-01) scale 100 of one
european call          when (on or after 2027-01-01) scale max(S - 100, 0) of one
digital call           when (on or after 2027-01-01) if (S >= 100) then scale 1 of one else zero
down and out call      until (S <= 90) (when (on or after 2027-01-01) scale max(S - 100, 0) of one)
american put           anytime (always) scale max(100 - S, 0) of one
autocallable           when (on or after 2026-12-25) if (S >= 100) then scale 105 of one else ...
```

## Headline

**On a live BTC smile, a digital is not `N(d2)`, and the gap is hundreds of basis points.**

A cash-or-nothing digital paying 1 is `exp(-rT) N(d2)` under a single volatility. It is
also the limit of a call spread, and once each leg carries its own implied volatility the
two disagree by exactly `vega * dsigma/dK`. On an SVI slice fitted to Deribit's BTC
options, 37 days to expiry, forward 86,203, at-the-money implied 36.4%:

| K/F | N(d2) | call spread | difference |
|---|---|---|---|
| 0.90 | 0.78376 | 0.82516 | **+414 bps** |
| 0.95 | 0.64592 | 0.67580 | +299 bps |
| 1.00 | 0.47691 | 0.48418 | +73 bps |
| 1.05 | 0.31644 | 0.30318 | -133 bps |
| 1.10 | 0.19498 | 0.17242 | **-226 bps** |

The sign follows the slope of the smile, and the size is not a rounding error: four
percentage points of the payout at the 0.90 strike. A desk quoting binaries off `N(d2)`
with a smile this steep is quoting the wrong price, in the same direction, every time.

`test_the_skew_term_explains_the_difference` pins the decomposition itself: the call
spread equals `N(d2)` minus `vega * dsigma/dK` to three decimals, so the table above is
the identity doing its work rather than two numbers that happen to differ.

Regenerate it with `dune exec bin/main.exe -- study`. The slice in `data/svi_slice.txt` is
a snapshot with its provenance in the header: refit it from `vol-lab` with
`uv run python scripts/export_slice.py --out ../contract-lab/data/svi_slice.txt`, and the
numbers will move with the market.

## Try it

```sh
opam switch create . 5.4.1
opam install -y --deps-only --with-test .
dune test
dune exec bin/main.exe -- termsheet
dune exec bin/main.exe -- checks
dune exec bin/main.exe -- study
dune exec bin/main.exe -- study --json   # every command takes --json
```

`--json` is what [`vol-lab`](https://github.com/benoitrobinson/vol-lab)'s terminal panel
reads: its tab 9 draws the table above, the checks and the term sheets from this binary.

## How it is checked

There is no closed-form price for an autocallable and no published table this repository
trusts more than its own arithmetic, so every check is an identity that fails loudly if
either side is wrong. Every number below is printed by `dune exec bin/main.exe -- checks`,
so none of them has to be taken on trust.

| check | reference |
|---|---|
| European call and put on the lattice | Black-Scholes closed form, 10.4406 at 200 steps against 10.4506 |
| Black-Scholes itself | put-call parity to ten decimals, and the textbook 10.4506 |
| Digital | `cash * exp(-rT) * N(d2)`, 0.532325 |
| Down-and-out call with the barrier at zero | equals the vanilla, to nine decimals |
| Down-and-out call | Reiner-Rubinstein, 8.6617 against 8.6655, with the lattice aligned to the barrier after Boyle and Lau (1994) |
| American call, no dividends | equals the European call on the same tree, exactly |
| American put | 4.4864 at 500 steps, 4.4867 at 2000, early-exercise premium 0.64 |
| American put, again by Longstaff-Schwartz | 4.4584 +/- 0.0148 against the lattice's 4.4867, below it by 0.6%, which is the bias the method has |
| Monte Carlo | agrees with the lattice within three standard errors on every choice-free product |
| Simplifier | QCheck: `price (simplify c) = price c` on 300 random contracts |

## Design notes

**Why a GADT, and why a closed set of observables.** A closed set can be printed,
rewritten and compared, which is what the simplifier and the term-sheet printer need. A
constructor carrying an arbitrary `float -> float` closure would be more flexible and
completely opaque: no printing, no rewriting, no equality. The GADT buys the property that
`Scale` cannot be handed a boolean and `Cond` cannot be handed a float, checked at compile
time rather than by a validator.

**Why absorption is not pointwise.** `until o c` cannot be evaluated by taking the value
process of `c` and zeroing the nodes where `o` holds: the value at a node is already an
expectation over paths that ignore the barrier, so the root keeps the unbarriered price.
The test `test_pointwise_absorption_is_not_a_knock_out` pins this, and the pointwise
version returns the vanilla call to the last decimal. The version that works carries the
contract's own local cashflow, recovered as `v(i)` less the discounted expectation of
`v(i+1)`, and rebuilds the expectation over the surviving nodes. No product knows it is a
barrier.

**Why plain Monte Carlo refuses `anytime`, and what answers it.** A forward simulation
cannot see the holder's optimal decision: at a node you know what exercising pays, and the
value of waiting is an expectation over paths that have not happened yet. `Mc` refuses
such contracts rather than pricing them wrongly. `Lsm` is the answer of Longstaff and
Schwartz (2001): estimate the continuation value from the cross-section of paths by
regressing the realised discounted cashflow on functions of spot, and exercise when the
immediate payoff beats the fit. It is biased low by construction, because the rule is
fitted on the paths it is applied to, and the test holds it under the lattice for exactly
that reason rather than asserting equality.

## What this does not do

- One currency. `One` is one unit of the numeraire; multi-currency needs FX observables.
- ACT/365 and no holiday calendar. Real term sheets settle on business days.
- Continuous barriers are priced on a discretely monitored tree. The remaining error is
  quantified in the test rather than waved at.
- No credit, no collateral, no multi-asset payoffs.
- Longstaff-Schwartz handles `anytime` over a choice-free contract, which covers American
  options. A choice nested inside a choice would need a nested regression and is refused.
- The SVI slice is one expiry, fitted once from public mark quotes. It is a snapshot,
  not a surface, and nothing here refits it as the market moves.
- Rates and carry are set to zero in the study, which for a 37-day crypto option moves the
  table by less than the smile does, but is still a simplification.

## References

- Peyton Jones, Eber and Seward, "Composing contracts: an adventure in financial
  engineering" (ICFP 2000).
- Peyton Jones and Eber, "How to write a financial contract" (2003).
- Reiner and Rubinstein, "Breaking down the barriers" (Risk, 1991).
- Boyle and Lau, "Bumping up against the barrier with the binomial method" (1994).
- Bahr, Berthold and Elsman, "Certified symbolic management of financial multi-party
  contracts" (ICFP 2015).
