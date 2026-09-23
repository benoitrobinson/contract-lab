# contract-lab

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

**Not measured yet.** The study that gives this repository its number prices a
cash-or-nothing digital two ways on a fitted BTC smile: as `exp(-rT) N(d2)`, and as the
limit of a call spread where each leg carries its own implied volatility. The difference
is `vega * dsigma/dK`, and `test_the_skew_term_explains_the_difference` pins that identity
to three decimals.

`data/svi_slice.txt` currently holds the plan's illustrative parameters, clearly marked as
a placeholder. Until a real slice is exported from `vol-lab`, `dune exec bin/main.exe --
study` prints a table that exercises every code path and describes no market, and no
number from it belongs in a headline.

## Try it

```sh
opam switch create . 5.4.1
opam install -y --deps-only --with-test .
dune test
dune exec bin/main.exe -- termsheet
dune exec bin/main.exe -- checks
dune exec bin/main.exe -- study
```

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

**Why Monte Carlo refuses `anytime`.** A forward simulation cannot see the holder's
optimal decision. Least-squares Monte Carlo would, and is deliberately not here: pricing a
contract wrongly is worse than refusing it, so `has_choice` rejects the contract instead.

## What this does not do

- One currency. `One` is one unit of the numeraire; multi-currency needs FX observables.
- ACT/365 and no holiday calendar. Real term sheets settle on business days.
- Continuous barriers are priced on a discretely monitored tree. The remaining error is
  quantified in the test rather than waved at.
- No credit, no collateral, no multi-asset payoffs.
- The SVI slice is a fit exported from another repository, not a live surface.

## References

- Peyton Jones, Eber and Seward, "Composing contracts: an adventure in financial
  engineering" (ICFP 2000).
- Peyton Jones and Eber, "How to write a financial contract" (2003).
- Reiner and Rubinstein, "Breaking down the barriers" (Risk, 1991).
- Boyle and Lau, "Bumping up against the barrier with the binomial method" (1994).
- Bahr, Berthold and Elsman, "Certified symbolic management of financial multi-party
  contracts" (ICFP 2015).
