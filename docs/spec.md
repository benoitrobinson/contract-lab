# contract-lab spec

## The question

Peyton Jones, Eber and Seward showed in 2000 that derivatives are not a catalogue of
products but a handful of combinators: a contract is built from `zero`, `one`, `give`,
`and`, `or`, `scale`, `when`, `anytime` and `until`, and a pricer is an interpreter of
that algebra rather than one function per payoff. LexiFi turned that into a product.

This repo rebuilds the idea in OCaml, prices it two ways, and then asks one quantitative
question with it:

**A cash-or-nothing digital is worth `N(d2)` under Black-Scholes. A digital is also the
limit of a call spread. Once the smile has slope, those two statements disagree, because
the call spread picks up the change in implied volatility across strikes. How large is
that disagreement on a real BTC smile, in basis points of the cash payout?**

The answer is a number the DSL produces, not a paragraph. It is the deliverable that
distinguishes this from the several existing "composing contracts" repositories, which
implement the algebra and stop.

## What gets built

1. The contract algebra, with observables typed by a GADT so `Scale` cannot take a boolean
   and `Cond` cannot take a float.
2. A term-sheet printer: every product prints as something a human can check.
3. A CRR binomial interpreter where `when`, `anytime` and `until` are backward-induction
   operators, not special cases per product.
4. A Monte Carlo interpreter for the choice-free subset, with a static check that rejects
   contracts it cannot price rather than pricing them wrongly.
5. An algebraic simplifier, with a property test asserting that simplification never
   changes a price.
6. The digital study above, using an SVI slice exported from `vol-lab`.

## Validation, and why it is internal

Published option values are hard to cite exactly and easy to transcribe wrongly. Every
check here is either a closed form implemented in the repo, or an internal consistency
identity that fails loudly if either side is wrong:

| Check | Reference |
|---|---|
| European call and put on the lattice | Black-Scholes closed form; error falls as 1/steps |
| Black-Scholes itself | put-call parity, and call = 10.4506 for S=K=100, r=5%, sigma=20%, T=1 |
| Digital | closed form `cash * exp(-rT) * N(d2)` |
| Down-and-out call, barrier pushed to zero | equals the European call |
| Down-and-out call | Reiner-Rubinstein closed form, implemented here, with the lattice aligned to the barrier |
| American call, no dividends | equals the European call |
| American put | early-exercise premium positive, price converging in steps |
| Monte Carlo | agrees with the lattice within three standard errors on every choice-free product |
| Simplifier | QCheck: `price (simplify c) = price c` on random contracts |

## Constraints

- OCaml 5.4.1 in a local opam switch, dune, no dependency the stdlib can replace. The
  normal CDF and the random number stream are written here, so a fresh clone reproduces
  the same numbers.
- `dune build && dune test` passes from a fresh switch, with no network beyond `opam
  install`.
- The SVI slice is a committed JSON file of five parameters, exported from `vol-lab`.
  No market data, no employer material.

## Out of scope

Multi-currency and FX observables, day-count conventions and holiday calendars, credit,
multi-asset payoffs, and a parser: contracts are written as OCaml values.
