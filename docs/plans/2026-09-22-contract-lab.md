# contract-lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An OCaml library where a derivative is a value in a combinator algebra, priced by two interpreters (binomial lattice and Monte Carlo), and used to measure how far a digital's price moves away from `N(d2)` once the volatility smile has slope.

**Architecture:** `Obs` is a GADT of observables, so the type system separates `float obs` from `bool obs`. `Contract` is a plain variant over those observables. `Lattice` compiles a contract into a value process on a CRR tree, where `when`, `anytime` and `until` become the backward-induction operators discount, Snell envelope and absorption. `Mc` prices the choice-free subset along simulated paths, and refuses the rest at run time after a static check. `Simplify` rewrites contracts and is property-tested to preserve price. `Bs` holds the closed forms every test compares against.

**Tech Stack:** OCaml 5.4.1, dune 3, ppx_expect for term-sheet tests, qcheck-core and alcotest for property tests, ocamlformat. No numerical dependency: the normal CDF, the RNG and the closed forms are written here.

**Spec:** `docs/spec.md`

**Verified:** every OCaml snippet in Tasks 2 to 8 was compiled and run on OCaml 5.4.1 before this
plan was written. The expected values in the tests below are measured outputs, not guesses.

## Global Constraints

- OCaml 5.4.1 in a project-local switch (`_opam`, already created at `~/code/contract-lab`).
- `dune build @all && dune test` must pass from a fresh switch. `dune build @fmt` must be clean.
- No float equality in tests: every comparison uses an explicit tolerance, stated per test.
- Dates are integer days since 1970-01-01. Year fractions are ACT/365, stated in the README as a simplification, not hidden.
- Single currency. `One` is one unit of the numeraire. Multi-currency needs FX observables and is out of scope, stated in the README.
- Every closed form used as a reference is implemented in `lib/bs.ml` and cross-checked by an identity (parity, a limit, or agreement between two interpreters), never by a transcribed table value.
- Commits: one idea each, plain imperative subject under 50 characters, no AI attribution, spread over real working days.

---

### Task 1: Project skeleton

**Files:**
- Create: `dune-project`, `contract_lab.opam`, `lib/dune`, `test/dune`, `bin/dune`, `.gitignore`, `.ocamlformat`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a switch where `dune build && dune test` succeeds with one placeholder test.

- [ ] **Step 1: Install the tools in the local switch**

```bash
cd ~/code/contract-lab
opam install -y dune ppx_expect qcheck-core qcheck-alcotest alcotest ocamlformat
eval $(opam env)
dune --version && ocaml -version
```

Expected: dune 3.x, OCaml 5.4.1. Every later command assumes `eval $(opam env)` has run in
that shell.

- [ ] **Step 2: Write the project files**

`dune-project`:

```
(lang dune 3.0)
(name contract_lab)
```

`.ocamlformat`:

```
profile = default
version = 0.29.0
```

`.gitignore`:

```
_build/
_opam/
*.install
figures/*.png
```

`lib/dune`:

```
(library
 (name contract_lab)
 (inline_tests)
 (preprocess
  (pps ppx_expect)))
```

`test/dune`:

```
(test
 (name test_contract_lab)
 (libraries contract_lab alcotest qcheck-core qcheck-alcotest))
```

`bin/dune`:

```
(executable
 (name main)
 (libraries contract_lab))
```

- [ ] **Step 3: Write a placeholder library and test**

`lib/version.ml`:

```ocaml
let version = "0.1.0"
```

`test/test_contract_lab.ml`:

```ocaml
let test_version () =
  Alcotest.(check string) "version" "0.1.0" Contract_lab.Version.version

let () =
  Alcotest.run "contract-lab" [ ("smoke", [ Alcotest.test_case "version" `Quick test_version ]) ]
```

`bin/main.ml`:

```ocaml
let () = print_endline ("contract-lab " ^ Contract_lab.Version.version)
```

- [ ] **Step 4: Run the build**

Run: `dune build @all && dune test`
Expected: PASS, one test.

- [ ] **Step 5: Write CI**

`.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: "5.4.1"
      - run: opam install -y --deps-only --with-test .
      - run: opam exec -- dune build @all
      - run: opam exec -- dune test
```

`contract_lab.opam`:

```
opam-version: "2.0"
synopsis: "Financial contracts as a combinator algebra, priced on a lattice and by Monte Carlo"
maintainer: "Benoit Robinson"
authors: "Benoit Robinson"
license: "MIT"
depends: [
  "ocaml" {>= "5.4"}
  "dune" {>= "3.0"}
  "ppx_expect" {with-test}
  "qcheck-core" {with-test}
  "qcheck-alcotest" {with-test}
  "alcotest" {with-test}
]
build: [["dune" "build" "-p" name "-j" jobs]]
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add dune skeleton and CI"
```

---

### Task 2: Dates

**Files:**
- Create: `lib/date.ml`

**Interfaces:**
- Produces: `Date.t = int` (days since 1970-01-01), `of_ymd`, `to_ymd`, `to_string`,
  `add_days`, `compare`, `year_fraction : t -> t -> float` (ACT/365).

- [ ] **Step 1: Write the failing test**

`lib/date.ml`, tests only:

```ocaml
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
```

20718 is the measured value, and it checks out: 2026-09-22 is 20,718 days after the epoch.

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound value of_ymd`.

- [ ] **Step 3: Implement dates**

Prepend to `lib/date.ml` (Howard Hinnant's civil calendar algorithms, which are exact for
any year and avoid a calendar dependency):

```ocaml
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `dune runtest --auto-promote && dune test`
Expected: PASS. Check by hand that the promoted day number for 2026-09-22 is consistent:
`(2026 - 1970) * 365.25` is about 20,458, and the exact value is a few hundred more
because of the day-of-year offset.

- [ ] **Step 5: Commit**

```bash
git add lib/date.ml
git commit -m "Add civil dates and ACT/365 year fractions"
```

---

### Task 3: Observables

**Files:**
- Create: `lib/obs.ml`

**Interfaces:**
- Produces:
  - `type _ t` with constructors `Konst : float -> float t`, `Spot : float t`,
    `Add | Sub | Mul | Max : float t * float t -> float t`,
    `Ge | Le : float t * float t -> bool t`, `And | Or : bool t * bool t -> bool t`,
    `Not : bool t -> bool t`, `Always : bool t`, `AtOrAfter : Date.t -> bool t`,
    `Before : Date.t -> bool t`
  - `type state = { spot : float; today : Date.t }`
  - `val eval : 'a t -> state -> 'a`
  - `val to_string : 'a t -> string`

Why a GADT and a closed set of constructors, the one design decision to defend: a closed
set can be printed, rewritten and compared, which is what `Simplify` and the term-sheet
printer need. A constructor carrying an arbitrary `float -> float` closure would be more
flexible and completely opaque: no printing, no rewriting, no equality. The GADT buys the
property that `Scale` cannot be handed a boolean and `Cond` cannot be handed a float,
checked at compile time rather than by a validator.

- [ ] **Step 1: Write the failing test**

`lib/obs.ml`, tests only:

```ocaml
let%expect_test "arithmetic evaluates at a node" =
  let s = { spot = 120.0; today = Date.of_ymd 2026 9 22 } in
  Printf.printf "%.2f" (eval (Sub (Spot, Konst 100.0)) s);
  [%expect {| 20.00 |}]

let%expect_test "comparisons produce booleans" =
  let s = { spot = 120.0; today = Date.of_ymd 2026 9 22 } in
  Printf.printf "%b %b" (eval (Ge (Spot, Konst 100.0)) s) (eval (Le (Spot, Konst 100.0)) s);
  [%expect {| true false |}]

let%expect_test "dates compare against the node's date" =
  let s = { spot = 1.0; today = Date.of_ymd 2026 9 22 } in
  let expiry = Date.of_ymd 2026 12 25 in
  Printf.printf "%b %b" (eval (AtOrAfter expiry) s) (eval (Before expiry) s);
  [%expect {| false true |}]

let%expect_test "an observable prints as itself" =
  print_string (to_string (Max (Sub (Spot, Konst 100.0), Konst 0.0)));
  [%expect {| max(S - 100, 0) |}]
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound constructor Konst`.

- [ ] **Step 3: Implement observables**

```ocaml
type _ t =
  | Konst : float -> float t
  | Spot : float t
  | Add : float t * float t -> float t
  | Sub : float t * float t -> float t
  | Mul : float t * float t -> float t
  | Max : float t * float t -> float t
  | Ge : float t * float t -> bool t
  | Le : float t * float t -> bool t
  | And : bool t * bool t -> bool t
  | Or : bool t * bool t -> bool t
  | Not : bool t -> bool t
  | Always : bool t
  | AtOrAfter : Date.t -> bool t
  | Before : Date.t -> bool t

type state = { spot : float; today : Date.t }

let rec eval : type a. a t -> state -> a =
 fun o s ->
  match o with
  | Konst k -> k
  | Spot -> s.spot
  | Add (a, b) -> eval a s +. eval b s
  | Sub (a, b) -> eval a s -. eval b s
  | Mul (a, b) -> eval a s *. eval b s
  | Max (a, b) -> Float.max (eval a s) (eval b s)
  | Ge (a, b) -> eval a s >= eval b s
  | Le (a, b) -> eval a s <= eval b s
  | And (a, b) -> eval a s && eval b s
  | Or (a, b) -> eval a s || eval b s
  | Not a -> not (eval a s)
  | Always -> true
  | AtOrAfter d -> Date.compare s.today d >= 0
  | Before d -> Date.compare s.today d < 0

let num f =
  if Float.is_integer f then Printf.sprintf "%.0f" f else Printf.sprintf "%g" f

let rec to_string : type a. a t -> string =
 fun o ->
  match o with
  | Konst k -> num k
  | Spot -> "S"
  | Add (a, b) -> Printf.sprintf "(%s + %s)" (to_string a) (to_string b)
  | Sub (a, b) -> Printf.sprintf "%s - %s" (to_string a) (to_string b)
  | Mul (a, b) -> Printf.sprintf "%s * %s" (to_string a) (to_string b)
  | Max (a, b) -> Printf.sprintf "max(%s, %s)" (to_string a) (to_string b)
  | Ge (a, b) -> Printf.sprintf "%s >= %s" (to_string a) (to_string b)
  | Le (a, b) -> Printf.sprintf "%s <= %s" (to_string a) (to_string b)
  | And (a, b) -> Printf.sprintf "%s and %s" (to_string a) (to_string b)
  | Or (a, b) -> Printf.sprintf "%s or %s" (to_string a) (to_string b)
  | Not a -> Printf.sprintf "not (%s)" (to_string a)
  | Always -> "always"
  | AtOrAfter d -> Printf.sprintf "on or after %s" (Date.to_string d)
  | Before d -> Printf.sprintf "before %s" (Date.to_string d)
```

Note the `type a.` annotations: without them the recursive functions do not typecheck over
a GADT, because each branch refines the type differently.

- [ ] **Step 4: Run to verify it passes**

Run: `dune test`
Expected: PASS, 4 expect tests.

- [ ] **Step 5: Commit**

```bash
git add lib/obs.ml
git commit -m "Add GADT observables with evaluation and printing"
```

---

### Task 4: Contracts, products and term sheets

**Files:**
- Create: `lib/contract.ml`, `lib/products.ml`

**Interfaces:**
- Produces:
  - `Contract.t = Zero | One | Give of t | And of t * t | Or of t * t | Cond of bool Obs.t * t * t | Scale of float Obs.t * t | When of bool Obs.t * t | Anytime of bool Obs.t * t | Until of bool Obs.t * t`
  - `Contract.to_string : t -> string`
  - `Products.{zcb, european_call, european_put, digital_call, down_and_out_call, american_put, autocallable}`

- [ ] **Step 1: Write the failing test**

`lib/products.ml`, tests only:

```ocaml
let%expect_test "a call prints as a term sheet" =
  print_string (Contract.to_string (european_call ~strike:100.0 ~expiry:(Date.of_ymd 2026 12 25)));
  [%expect {| when (on or after 2026-12-25) scale max(S - 100, 0) of one |}]

let%expect_test "a digital prints as a term sheet" =
  print_string
    (Contract.to_string
       (digital_call ~strike:100.0 ~expiry:(Date.of_ymd 2026 12 25) ~cash:1.0));
  [%expect
    {| when (on or after 2026-12-25) if (S >= 100) then scale 1 of one else zero |}]

let%expect_test "a knock-out wraps the contract it cancels" =
  print_string
    (Contract.to_string
       (down_and_out_call ~strike:100.0 ~barrier:80.0 ~expiry:(Date.of_ymd 2026 12 25)));
  [%expect
    {| until (S <= 80) (when (on or after 2026-12-25) scale max(S - 100, 0) of one) |}]

let%expect_test "an autocallable is ten lines of algebra" =
  let d = Date.of_ymd in
  let c =
    autocallable ~observations:[ d 2026 12 25; d 2027 3 25; d 2027 6 25 ] ~trigger:100.0
      ~coupon:5.0 ~notional:100.0 ~ki_barrier:60.0
  in
  print_string (String.sub (Contract.to_string c) 0 60);
  [%expect {| when (on or after 2026-12-25) if (S >= 100) then scale |}]
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound module Contract`.

- [ ] **Step 3: Implement contracts**

`lib/contract.ml`:

```ocaml
(** The combinator algebra of Peyton Jones, Eber and Seward. `One` is one unit
    of the single numeraire currency: multi-currency needs FX observables and is
    out of scope. *)
type t =
  | Zero
  | One
  | Give of t
  | And of t * t
  | Or of t * t
  | Cond of bool Obs.t * t * t
  | Scale of float Obs.t * t
  | When of bool Obs.t * t
  | Anytime of bool Obs.t * t
  | Until of bool Obs.t * t

let rec to_string c =
  match c with
  | Zero -> "zero"
  | One -> "one"
  | Give c -> Printf.sprintf "give (%s)" (to_string c)
  | And (a, b) -> Printf.sprintf "(%s) and (%s)" (to_string a) (to_string b)
  | Or (a, b) -> Printf.sprintf "(%s) or (%s)" (to_string a) (to_string b)
  | Cond (o, a, b) ->
      Printf.sprintf "if (%s) then %s else %s" (Obs.to_string o) (to_string a) (to_string b)
  | Scale (o, c) -> Printf.sprintf "scale %s of %s" (Obs.to_string o) (to_string c)
  | When (o, c) -> Printf.sprintf "when (%s) %s" (Obs.to_string o) (to_string c)
  | Anytime (o, c) -> Printf.sprintf "anytime (%s) %s" (Obs.to_string o) (to_string c)
  | Until (o, c) -> Printf.sprintf "until (%s) (%s)" (Obs.to_string o) (to_string c)
```

- [ ] **Step 4: Implement the products**

Prepend to `lib/products.ml`:

```ocaml
open Contract

let cash amount = Scale (Obs.Konst amount, One)
let zcb ~date ~amount = When (Obs.AtOrAfter date, cash amount)

let european_call ~strike ~expiry =
  When
    ( Obs.AtOrAfter expiry,
      Scale (Obs.Max (Obs.Sub (Obs.Spot, Obs.Konst strike), Obs.Konst 0.0), One) )

let european_put ~strike ~expiry =
  When
    ( Obs.AtOrAfter expiry,
      Scale (Obs.Max (Obs.Sub (Obs.Konst strike, Obs.Spot), Obs.Konst 0.0), One) )

let digital_call ~strike ~expiry ~cash:c =
  When (Obs.AtOrAfter expiry, Cond (Obs.Ge (Obs.Spot, Obs.Konst strike), cash c, Zero))

let down_and_out_call ~strike ~barrier ~expiry =
  Until (Obs.Le (Obs.Spot, Obs.Konst barrier), european_call ~strike ~expiry)

(* The holder may exercise at any node of the tree, whose horizon is the expiry,
   so the exercise window is `Always` rather than a date test. *)
let american_put ~strike =
  Anytime
    (Obs.Always, Scale (Obs.Max (Obs.Sub (Obs.Konst strike, Obs.Spot), Obs.Konst 0.0), One))

(* Pays a growing coupon plus notional on the first observation date where spot
   is at or above the trigger. If it never triggers, the holder is long the
   downside below the knock-in barrier at the last date. *)
let autocallable ~observations ~trigger ~coupon ~notional ~ki_barrier =
  let redeem n = cash (notional +. (coupon *. float_of_int n)) in
  let final =
    Cond
      ( Obs.Ge (Obs.Spot, Obs.Konst ki_barrier),
        cash notional,
        Scale (Obs.Mul (Obs.Konst (notional /. 100.0), Obs.Spot), One) )
  in
  let rec build n = function
    | [] -> Zero
    | [ last ] -> When (Obs.AtOrAfter last, Cond (Obs.Ge (Obs.Spot, Obs.Konst trigger), redeem n, final))
    | d :: rest ->
        When
          ( Obs.AtOrAfter d,
            Cond (Obs.Ge (Obs.Spot, Obs.Konst trigger), redeem n, build (n + 1) rest) )
  in
  build 1 observations
```

- [ ] **Step 5: Run and promote the expected term sheets**

Run: `dune runtest --auto-promote && dune test`
Expected: PASS. Read every promoted term sheet: this is the test that catches a product
built wrongly, and promoting without reading defeats it.

- [ ] **Step 6: Commit**

```bash
git add lib/contract.ml lib/products.ml
git commit -m "Add the contract algebra and a product library"
```

---

### Task 5: Closed forms

**Files:**
- Create: `lib/bs.ml`

**Interfaces:**
- Produces: `Bs.{norm_cdf, call, put, vega, digital_call, down_and_out_call}`, all taking
  `~s ~k ~r ~sigma ~t` and returning a price.

- [ ] **Step 1: Write the failing test**

`lib/bs.ml`, tests only:

```ocaml
let%expect_test "the normal cdf is symmetric and anchored" =
  Printf.printf "%.6f %.6f %.6f" (norm_cdf 0.0) (norm_cdf 1.96) (norm_cdf (-1.96));
  [%expect {| 0.500000 0.975002 0.024998 |}]

let%expect_test "the textbook call value" =
  Printf.printf "%.4f" (call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0);
  [%expect {| 10.4506 |}]

let%expect_test "put-call parity holds" =
  let c = call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let p = put ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%.10f" (c -. p -. (100.0 -. (100.0 *. exp (-0.05))));
  [%expect {| 0.0000000000 |}]

let%expect_test "a digital is the discounted probability of finishing in the money" =
  let d = digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0 in
  Printf.printf "%.6f" d;
  [%expect {| 0.532325 |}]

let%expect_test "a barrier at zero is just a call" =
  let c = call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let b = down_and_out_call ~s:100.0 ~k:100.0 ~h:1e-8 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%.8f" (c -. b);
  [%expect {| 0.00000000 |}]

let%expect_test "a barrier just under spot is nearly worthless" =
  let b = down_and_out_call ~s:100.0 ~k:100.0 ~h:99.99 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%b" (b < 0.05);
  [%expect {| true |}]
```

All six values are measured. `norm_cdf 1.96 = 0.975002` against the table value 0.975, and
the call is the textbook 10.4506.

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound value norm_cdf`.

- [ ] **Step 3: Implement the closed forms**

```ocaml
(* Abramowitz and Stegun 26.2.17, absolute error below 7.5e-8. Written here so a
   clone reproduces every number without a numerical dependency. *)
let norm_cdf x =
  let b1 = 0.319381530
  and b2 = -0.356563782
  and b3 = 1.781477937
  and b4 = -1.821255978
  and b5 = 1.330274429
  and p = 0.2316419 in
  let ax = Float.abs x in
  let k = 1.0 /. (1.0 +. (p *. ax)) in
  let poly = (((((((b5 *. k) +. b4) *. k) +. b3) *. k) +. b2) *. k +. b1) *. k in
  let phi = exp (-0.5 *. ax *. ax) /. sqrt (2.0 *. Float.pi) in
  let upper_tail = phi *. poly in
  if x >= 0.0 then 1.0 -. upper_tail else upper_tail

let d1 ~s ~k ~r ~sigma ~t =
  ((log (s /. k) +. ((r +. (0.5 *. sigma *. sigma)) *. t)) /. (sigma *. sqrt t))

let d2 ~s ~k ~r ~sigma ~t = d1 ~s ~k ~r ~sigma ~t -. (sigma *. sqrt t)

let call ~s ~k ~r ~sigma ~t =
  if t <= 0.0 then Float.max (s -. k) 0.0
  else
    (s *. norm_cdf (d1 ~s ~k ~r ~sigma ~t))
    -. (k *. exp (-.r *. t) *. norm_cdf (d2 ~s ~k ~r ~sigma ~t))

let put ~s ~k ~r ~sigma ~t =
  if t <= 0.0 then Float.max (k -. s) 0.0
  else
    (k *. exp (-.r *. t) *. norm_cdf (-.d2 ~s ~k ~r ~sigma ~t))
    -. (s *. norm_cdf (-.d1 ~s ~k ~r ~sigma ~t))

let vega ~s ~k ~r ~sigma ~t =
  let d = d1 ~s ~k ~r ~sigma ~t in
  s *. sqrt t *. exp (-0.5 *. d *. d) /. sqrt (2.0 *. Float.pi)

let digital_call ~s ~k ~r ~sigma ~t ~cash =
  cash *. exp (-.r *. t) *. norm_cdf (d2 ~s ~k ~r ~sigma ~t)

(* Reiner and Rubinstein (1991), down-and-out call with the strike above the
   barrier, no rebate, no dividends: c = A - C in Haug's decomposition. *)
let down_and_out_call ~s ~k ~h ~r ~sigma ~t =
  let sqrt_t = sqrt t in
  let mu = (r -. (0.5 *. sigma *. sigma)) /. (sigma *. sigma) in
  let x1 = (log (s /. k) /. (sigma *. sqrt_t)) +. ((1.0 +. mu) *. sigma *. sqrt_t) in
  let y1 =
    (log (h *. h /. (s *. k)) /. (sigma *. sqrt_t)) +. ((1.0 +. mu) *. sigma *. sqrt_t)
  in
  let a =
    (s *. norm_cdf x1) -. (k *. exp (-.r *. t) *. norm_cdf (x1 -. (sigma *. sqrt_t)))
  in
  let c =
    (s *. ((h /. s) ** (2.0 *. (mu +. 1.0))) *. norm_cdf y1)
    -. (k *. exp (-.r *. t) *. ((h /. s) ** (2.0 *. mu))
        *. norm_cdf (y1 -. (sigma *. sqrt_t)))
  in
  Float.max (a -. c) 0.0
```

- [ ] **Step 4: Run to verify it passes**

Run: `dune runtest --auto-promote && dune test`
Expected: PASS, 6 expect tests. The call must promote to `10.4506`; if it does not, the
formula is wrong, not the reference.

- [ ] **Step 5: Commit**

```bash
git add lib/bs.ml
git commit -m "Add Black-Scholes and barrier closed forms"
```

---

### Task 6: The lattice interpreter

**Files:**
- Create: `lib/lattice.ml`

**Interfaces:**
- Produces:
  - `type model = { s0 : float; r : float; sigma : float; today : Date.t; horizon : Date.t; steps : int }`
  - `type process = float array array`
  - `val value : model -> Contract.t -> process`
  - `val price : model -> Contract.t -> float`
  - `val boyle_lau_steps : s:float -> h:float -> sigma:float -> t:float -> max_steps:int -> int`

A contract compiles to a value process: a triangular array where `v.(i).(j)` is what the
contract is worth at step `i` after `j` up moves. The combinators become operators on
processes, and every product in the library is priced by the same three lines of backward
induction rather than by its own formula. That is the whole point of the algebra.

- [ ] **Step 1: Write the failing test**

`lib/lattice.ml`, tests only:

```ocaml
let%expect_test "a zero coupon bond discounts" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 100 } in
  let p = price m (Products.zcb ~date:horizon ~amount:100.0) in
  Printf.printf "%.4f" p;
  [%expect {| 95.1229 |}]

let%expect_test "the European call converges to Black-Scholes" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let at steps =
    let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps } in
    price m (Products.european_call ~strike:100.0 ~expiry:horizon)
  in
  Printf.printf "%b %b"
    (Float.abs (at 200 -. bs) < 0.05)
    (Float.abs ((at 2000 +. at 2001) /. 2.0 -. bs) < 0.01);
  [%expect {| true true |}]

let%expect_test "averaging two adjacent step counts removes the oscillation" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  let at steps =
    let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps } in
    price m (Products.european_call ~strike:100.0 ~expiry:horizon)
  in
  let single = Float.abs (at 501 -. bs) in
  let averaged = Float.abs (((at 500 +. at 501) /. 2.0) -. bs) in
  Printf.printf "%b" (averaged < single);
  [%expect {| true |}]

let%expect_test "the digital matches its closed form" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 2000 } in
  let lattice = price m (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0) in
  let closed = Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0 in
  Printf.printf "%b" (Float.abs (lattice -. closed) < 0.02);
  [%expect {| true |}]

let%expect_test "give negates and and adds" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 50 } in
  let b = Products.zcb ~date:horizon ~amount:100.0 in
  Printf.printf "%.8f" (price m (Contract.And (b, Contract.Give b)));
  [%expect {| 0.00000000 |}]
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound value price`.

- [ ] **Step 3: Implement the lattice**

```ocaml
type model = {
  s0 : float;
  r : float;
  sigma : float;
  today : Date.t;
  horizon : Date.t;
  steps : int;
}

(** `process.(i).(j)` is the value at step `i` after `j` up moves. *)
type process = float array array

let dt m = Date.year_fraction m.today m.horizon /. float_of_int m.steps
let up m = exp (m.sigma *. sqrt (dt m))

let p_up m =
  let u = up m in
  let d = 1.0 /. u in
  (exp (m.r *. dt m) -. d) /. (u -. d)

let discount m = exp (-.m.r *. dt m)
let spot m i j = m.s0 *. (up m ** float_of_int ((2 * j) - i))

let date_at m i =
  Date.add_days m.today (int_of_float (Float.round (float_of_int i *. dt m *. 365.0)))

let state m i j : Obs.state = { spot = spot m i j; today = date_at m i }
let empty m = Array.init (m.steps + 1) (fun i -> Array.make (i + 1) 0.0)
let const m v = Array.init (m.steps + 1) (fun i -> Array.make (i + 1) v)

let map f (a : process) : process = Array.map (Array.map f) a

let map2 f (a : process) (b : process) : process =
  Array.mapi (fun i row -> Array.mapi (fun j x -> f x b.(i).(j)) row) a

let obs_process : type a. model -> a Obs.t -> a array array =
 fun m o -> Array.init (m.steps + 1) (fun i -> Array.init (i + 1) (fun j -> Obs.eval o (state m i j)))

(** Discounted expectation of the next step, taken from `v`. *)
let cont m (v : process) i j =
  let p = p_up m in
  discount m *. ((p *. v.(i + 1).(j + 1)) +. ((1.0 -. p) *. v.(i + 1).(j)))

(** `when o c`: acquire `c` at the first node where `o` holds. *)
let disc_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then v.(n).(j) else 0.0)
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      out.(i).(j) <- (if cond.(i).(j) then v.(i).(j) else cont m out i j)
    done
  done;
  out

(** `anytime o c`: the Snell envelope, exercise when it beats continuation. *)
let snell_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then v.(n).(j) else 0.0)
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      let continuation = cont m out i j in
      out.(i).(j) <-
        (if cond.(i).(j) then Float.max v.(i).(j) continuation else continuation)
    done
  done;
  out

(** The cash `v` pays at a node, recovered from its own process: what it is
    worth now, less what its future is worth. Zero everywhere except where the
    contract actually pays. *)
let local_cash m (v : process) i j =
  if i = m.steps then v.(m.steps).(j) else v.(i).(j) -. cont m v i j

(** `until o c`: `c`, abandoned at the first node where `o` holds. The
    recursion matters: zeroing the value process pointwise leaves the parent
    nodes with the unbarriered value, which is the European price, and is wrong.
    `absorb_pointwise` below exists to demonstrate exactly that. *)
let absorb_op m (cond : bool array array) (v : process) : process =
  let n = m.steps in
  let out = empty m in
  for j = 0 to n do
    out.(n).(j) <- (if cond.(n).(j) then 0.0 else v.(n).(j))
  done;
  for i = n - 1 downto 0 do
    for j = 0 to i do
      out.(i).(j) <-
        (if cond.(i).(j) then 0.0 else local_cash m v i j +. cont m out i j)
    done
  done;
  out

let absorb_pointwise (cond : bool array array) (v : process) : process =
  Array.mapi (fun i row -> Array.mapi (fun j x -> if cond.(i).(j) then 0.0 else x) row) v

let select (cond : bool array array) (a : process) (b : process) : process =
  Array.mapi (fun i row -> Array.mapi (fun j c -> if c then a.(i).(j) else b.(i).(j)) row) cond

let rec value m (c : Contract.t) : process =
  match c with
  | Zero -> const m 0.0
  | One -> const m 1.0
  | Give c -> map (fun v -> -.v) (value m c)
  | And (a, b) -> map2 ( +. ) (value m a) (value m b)
  | Or (a, b) -> map2 Float.max (value m a) (value m b)
  | Cond (o, a, b) -> select (obs_process m o) (value m a) (value m b)
  | Scale (o, c) -> map2 ( *. ) (obs_process m o) (value m c)
  | When (o, c) -> disc_op m (obs_process m o) (value m c)
  | Anytime (o, c) -> snell_op m (obs_process m o) (value m c)
  | Until (o, c) -> absorb_op m (obs_process m o) (value m c)

let price m c = (value m c).(0).(0)

(** Boyle and Lau (1994): put a layer of the tree on the barrier, or the price
    oscillates with the step count as the barrier drifts between layers. Returns
    the largest aligned step count at or below `max_steps`. *)
let boyle_lau_steps ~s ~h ~sigma ~t ~max_steps =
  let ratio = log (s /. h) in
  if ratio <= 0.0 then max_steps
  else begin
    let best = ref 1 in
    let k = ref 1 in
    let continue_ = ref true in
    while !continue_ do
      let n = int_of_float (float_of_int (!k * !k) *. sigma *. sigma *. t /. (ratio *. ratio)) in
      if n > max_steps then continue_ := false
      else begin
        if n > !best then best := n;
        incr k
      end
    done;
    Stdlib.max !best 2
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `dune runtest --auto-promote && dune test`
Expected: PASS, 5 expect tests. Measured on the reference implementation: the bond is
95.1229, which is `100 * exp(-0.05)`; the call is 10.4406 at 200 steps and 10.4432 at 2000,
against Black-Scholes 10.4506, and averaging steps 2000 and 2001 gives 10.4441; the digital
is 0.540712 against a closed form of 0.532325. Anything far from these means the
discounting or the node indexing is wrong.

- [ ] **Step 5: Commit**

```bash
git add lib/lattice.ml
git commit -m "Compile contracts to a value process on a CRR tree"
```

---

### Task 7: Early exercise

**Files:**
- Create: `test/test_american.ml`
- Modify: `test/dune` (add the new test executable or include it in the existing one)

**Interfaces:**
- Consumes: `Lattice.{model, price}`, `Products.{american_put, european_put, european_call}`.
- Produces: no new code, three identities that fail if `snell_op` is wrong.

- [ ] **Step 1: Write the failing test**

```ocaml
let m steps =
  {
    Contract_lab.Lattice.s0 = 36.0;
    r = 0.06;
    sigma = 0.2;
    today = Contract_lab.Date.of_ymd 2026 1 1;
    horizon = Contract_lab.Date.of_ymd 2027 1 1;
    steps;
  }

let price steps c = Contract_lab.Lattice.price (m steps) c
let expiry = Contract_lab.Date.of_ymd 2027 1 1

let test_american_call_equals_european () =
  (* With no dividends it is never optimal to exercise a call early. On the same
     tree the two prices are identical, not merely close. *)
  let american =
    Contract_lab.Contract.Anytime
      ( Contract_lab.Obs.Always,
        Contract_lab.Contract.Scale
          ( Contract_lab.Obs.Max
              (Contract_lab.Obs.Sub (Contract_lab.Obs.Spot, Contract_lab.Obs.Konst 40.0),
               Contract_lab.Obs.Konst 0.0),
            Contract_lab.Contract.One ) )
  in
  let european = Contract_lab.Products.european_call ~strike:40.0 ~expiry in
  Alcotest.(check (float 1e-9)) "american call = european" (price 500 european) (price 500 american)

let test_early_exercise_premium_is_positive () =
  let american = Contract_lab.Products.american_put ~strike:40.0 in
  let european = Contract_lab.Products.european_put ~strike:40.0 ~expiry in
  let premium = price 500 american -. price 500 european in
  Alcotest.(check bool) "premium positive" true (premium > 0.01)

let test_american_put_converges () =
  let american = Contract_lab.Products.american_put ~strike:40.0 in
  let a = price 500 american and b = price 2000 american in
  Alcotest.(check bool) "converged" true (Float.abs (a -. b) < 0.01);
  (* Sanity: deep in the money at S=36, K=40, the put is worth at least its
     intrinsic value of 4. *)
  Alcotest.(check bool) "at least intrinsic" true (b >= 4.0)
```

Register the cases in `test/test_contract_lab.ml`'s `Alcotest.run` list.

- [ ] **Step 2: Run to verify it fails, then passes**

Run: `dune test`
Expected: PASS. Measured on the reference implementation: the American put is 4.4864 at 500
steps and 4.4867 at 2000, against a European put of 3.8436, so the early-exercise premium is
0.64. That price also sits on the published Longstaff-Schwartz benchmark for these
parameters (S=36, K=40, r=6%, sigma=20%, T=1), which is a free external check. Do not weaken
a tolerance to make this pass.

- [ ] **Step 3: Commit**

```bash
git add test
git commit -m "Check early exercise against three identities"
```

---

### Task 8: Barriers, and what absorption actually requires

**Files:**
- Create: `test/test_barrier.ml`
- Modify: `test/test_contract_lab.ml`

**Interfaces:**
- Consumes: `Lattice.{price, value, absorb_pointwise, boyle_lau_steps}`, `Bs.down_and_out_call`.

This task produces the repo's one genuine finding about the algebra: the value process of
a knock-out cannot be obtained by zeroing the underlying contract's process at breached
nodes. Doing that returns the unbarriered price, because the parent nodes were computed
before the barrier existed. Absorption has to run inside the backward induction, carrying
the contract's own cashflows. The test states both.

- [ ] **Step 1: Write the failing test**

```ocaml
let today = Contract_lab.Date.of_ymd 2026 1 1
let expiry = Contract_lab.Date.of_ymd 2027 1 1

let model steps =
  { Contract_lab.Lattice.s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon = expiry; steps }

let test_knock_out_matches_the_closed_form () =
  let steps =
    Contract_lab.Lattice.boyle_lau_steps ~s:100.0 ~h:90.0 ~sigma:0.2 ~t:1.0 ~max_steps:3000
  in
  let lattice =
    Contract_lab.Lattice.price (model steps)
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry)
  in
  let closed =
    Contract_lab.Bs.down_and_out_call ~s:100.0 ~k:100.0 ~h:90.0 ~r:0.05 ~sigma:0.2 ~t:1.0
  in
  (* Discrete monitoring on a tree prices a knock-out above continuous
     monitoring, so the lattice sits slightly above the closed form. *)
  Alcotest.(check bool) "within 3% of closed form" true
    (Float.abs (lattice -. closed) /. closed < 0.03);
  Alcotest.(check bool) "cheaper than the vanilla" true
    (lattice < Contract_lab.Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0)

let test_a_barrier_at_zero_is_the_vanilla () =
  let lattice =
    Contract_lab.Lattice.price (model 500)
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:1e-8 ~expiry)
  in
  let vanilla =
    Contract_lab.Lattice.price (model 500)
      (Contract_lab.Products.european_call ~strike:100.0 ~expiry)
  in
  Alcotest.(check (float 1e-9)) "same as vanilla" vanilla lattice

let test_pointwise_absorption_is_not_a_knock_out () =
  let m = model 500 in
  let underlying = Contract_lab.Products.european_call ~strike:100.0 ~expiry in
  let cond =
    Contract_lab.Lattice.obs_process m
      (Contract_lab.Obs.Le (Contract_lab.Obs.Spot, Contract_lab.Obs.Konst 90.0))
  in
  let wrong =
    (Contract_lab.Lattice.absorb_pointwise cond (Contract_lab.Lattice.value m underlying)).(0).(0)
  in
  let right =
    Contract_lab.Lattice.price m
      (Contract_lab.Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry)
  in
  let vanilla = Contract_lab.Lattice.price m underlying in
  Alcotest.(check (float 1e-9)) "pointwise returns the vanilla price" vanilla wrong;
  Alcotest.(check bool) "the real knock-out is worth less" true (right < vanilla -. 0.5)
```

- [ ] **Step 2: Run it**

Run: `dune test`
Expected: PASS. Measured on the reference implementation: Boyle-Lau picks 2825 steps for a
90 barrier, and the lattice gives 8.6617 against the closed form's 8.6655, a relative error
of 0.04%. The pointwise version returns 10.4466, which is the vanilla call to the last
decimal. If the barrier test fails by more than 3%, check the alignment before touching the
formula: an unaligned tree can be several percent out on its own.

- [ ] **Step 3: Write the finding down**

Add to `docs/notes.md`:

```markdown
## Absorption is not pointwise

`until o c` cannot be evaluated by taking the value process of `c` and zeroing the nodes
where `o` holds. The value at a node is already an expectation over paths that ignore the
barrier, so the root keeps the unbarriered price. `test_pointwise_absorption_is_not_a_knock_out`
pins this: the pointwise version returns the vanilla call to the last decimal.

The version that works carries the contract's own local cashflow, recovered as
`v(i) - discounted expectation of v(i+1)`, and rebuilds the expectation over the surviving
nodes. That keeps the combinator compositional: no product knows it is a barrier.

Open question for anyone who has the 2003 paper to hand: check how `absorb` is defined
there and whether the definition assumes payments only at the horizon.
```

- [ ] **Step 4: Commit**

```bash
git add test docs/notes.md
git commit -m "Price knock-outs and show pointwise absorption fails"
```

---

### Task 9: The Monte Carlo interpreter

**Files:**
- Create: `lib/mc.ml`

**Interfaces:**
- Produces:
  - `type model = { s0 : float; r : float; sigma : float; today : Date.t; horizon : Date.t; steps : int; paths : int; seed : int }`
  - `exception Unsupported of string`
  - `val has_choice : Contract.t -> bool`
  - `val price : model -> Contract.t -> float * float` (price and standard error)

A second interpreter of the same algebra, which is the argument for the algebra: no
product is rewritten to be simulated. `Or` and `Anytime` need the holder's optimal
decision, which a forward simulation cannot see, so `has_choice` rejects those contracts
instead of returning a plausible wrong number. Least-squares Monte Carlo would lift that
restriction and is deliberately left out.

- [ ] **Step 1: Write the failing test**

`lib/mc.ml`, tests only:

```ocaml
let%expect_test "contracts with a choice are refused" =
  let c = Products.american_put ~strike:40.0 in
  Printf.printf "%b %b" (has_choice c)
    (has_choice (Products.european_call ~strike:100.0 ~expiry:(Date.of_ymd 2027 1 1)));
  [%expect {| true false |}]

let%expect_test "the European call agrees with Black-Scholes within three standard errors" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 50; paths = 200_000; seed = 7 } in
  let p, se = price m (Products.european_call ~strike:100.0 ~expiry:horizon) in
  let bs = Bs.call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 in
  Printf.printf "%b" (Float.abs (p -. bs) < 3.0 *. se);
  [%expect {| true |}]

let%expect_test "the digital agrees with its closed form within three standard errors" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 50; paths = 200_000; seed = 11 } in
  let p, se = price m (Products.digital_call ~strike:100.0 ~expiry:horizon ~cash:1.0) in
  let closed = Bs.digital_call ~s:100.0 ~k:100.0 ~r:0.05 ~sigma:0.2 ~t:1.0 ~cash:1.0 in
  Printf.printf "%b" (Float.abs (p -. closed) < 3.0 *. se);
  [%expect {| true |}]

let%expect_test "a knock-out is worth less than the vanilla it wraps" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 250; paths = 100_000; seed = 3 } in
  let ko, _ = price m (Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry:horizon) in
  let vanilla, _ = price m (Products.european_call ~strike:100.0 ~expiry:horizon) in
  Printf.printf "%b" (ko < vanilla -. 0.5);
  [%expect {| true |}]

let%expect_test "the same seed gives the same price" =
  let today = Date.of_ymd 2026 1 1 in
  let horizon = Date.of_ymd 2027 1 1 in
  let m = { s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 20; paths = 5_000; seed = 42 } in
  let c = Products.european_call ~strike:100.0 ~expiry:horizon in
  Printf.printf "%b" (fst (price m c) = fst (price m c));
  [%expect {| true |}]
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound value has_choice`.

- [ ] **Step 3: Implement the interpreter**

```ocaml
type model = {
  s0 : float;
  r : float;
  sigma : float;
  today : Date.t;
  horizon : Date.t;
  steps : int;
  paths : int;
  seed : int;
}

exception Unsupported of string

let rec has_choice (c : Contract.t) =
  match c with
  | Zero | One -> false
  | Or _ | Anytime _ -> true
  | Give c | Scale (_, c) | When (_, c) | Until (_, c) -> has_choice c
  | And (a, b) -> has_choice a || has_choice b
  | Cond (_, a, b) -> has_choice a || has_choice b

let dt m = Date.year_fraction m.today m.horizon /. float_of_int m.steps

let date_at m i =
  Date.add_days m.today (int_of_float (Float.round (float_of_int i *. dt m *. 365.0)))

(* Box-Muller on the stdlib generator. OCaml 5's Random is LXM and splittable,
   so a fixed seed reproduces a run on any machine running the same compiler. *)
let normal rng =
  let u1 = Float.max 1e-12 (Random.State.float rng 1.0) in
  let u2 = Random.State.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)

let simulate m rng =
  let dt = dt m in
  let drift = (m.r -. (0.5 *. m.sigma *. m.sigma)) *. dt in
  let vol = m.sigma *. sqrt dt in
  let path = Array.make (m.steps + 1) m.s0 in
  for i = 1 to m.steps do
    path.(i) <- path.(i - 1) *. exp (drift +. (vol *. normal rng))
  done;
  path

let state m path i : Obs.state = { spot = path.(i); today = date_at m i }

(* Present value at step `i`, of a contract whose cashflows after step `limit`
   have been cancelled by an enclosing `until`. *)
let rec pv m path ~limit i (c : Contract.t) =
  match c with
  | Zero -> 0.0
  | One -> 1.0
  | Give c -> -.pv m path ~limit i c
  | And (a, b) -> pv m path ~limit i a +. pv m path ~limit i b
  | Or _ -> raise (Unsupported "or")
  | Anytime _ -> raise (Unsupported "anytime")
  | Scale (o, c) -> Obs.eval o (state m path i) *. pv m path ~limit i c
  | Cond (o, a, b) ->
      if Obs.eval o (state m path i) then pv m path ~limit i a else pv m path ~limit i b
  | When (o, c) -> (
      match first_true m path ~from:i ~until:limit o with
      | None -> 0.0
      | Some j -> exp (-.m.r *. dt m *. float_of_int (j - i)) *. pv m path ~limit j c)
  | Until (o, c) -> (
      match first_true m path ~from:i ~until:limit o with
      | None -> pv m path ~limit i c
      | Some j -> if j <= i then 0.0 else pv m path ~limit:(j - 1) i c)

and first_true m path ~from ~until o =
  let rec go i = if i > until then None else if Obs.eval o (state m path i) then Some i else go (i + 1) in
  go from

let price m c =
  if has_choice c then raise (Unsupported "contract contains a holder choice");
  let rng = Random.State.make [| m.seed |] in
  let sum = ref 0.0 and sum_sq = ref 0.0 in
  for _ = 1 to m.paths do
    let v = pv m (simulate m rng) ~limit:m.steps 0 in
    sum := !sum +. v;
    sum_sq := !sum_sq +. (v *. v)
  done;
  let n = float_of_int m.paths in
  let mean = !sum /. n in
  let var = Float.max 0.0 ((!sum_sq /. n) -. (mean *. mean)) in
  (mean, sqrt (var /. n))
```

Note: `pv m (simulate m rng) ~limit:m.steps 0` passes the path positionally before the
labelled argument; if the compiler objects, bind the path first with `let path = simulate
m rng in`.

- [ ] **Step 4: Run to verify it passes**

Run: `dune test`
Expected: PASS, 5 expect tests. The three-standard-error tests are the real check: if the
lattice and the simulation disagree, one of the two interpreters is wrong and the algebra
has caught it.

- [ ] **Step 5: Commit**

```bash
git add lib/mc.ml
git commit -m "Add a Monte Carlo interpreter for choice-free contracts"
```

---

### Task 10: The simplifier and its property

**Files:**
- Create: `lib/simplify.ml`, `test/test_simplify.ml`
- Modify: `test/test_contract_lab.ml`

**Interfaces:**
- Produces: `Simplify.simplify : Contract.t -> Contract.t`.

The rewrite rules are only interesting if they are safe, and "safe" has a testable
meaning: the price does not move. QCheck generates random contracts, both interpreters
price the original and the simplified form, and the test fails if they differ. This is the
part of the repo that an interviewer will push on, so the generator must produce contracts
that actually exercise the rules.

- [ ] **Step 1: Write the failing test**

`test/test_simplify.ml`:

```ocaml
open Contract_lab

let today = Date.of_ymd 2026 1 1
let horizon = Date.of_ymd 2027 1 1
let model = { Lattice.s0 = 100.0; r = 0.05; sigma = 0.2; today; horizon; steps = 60 }

let float_obs =
  let open QCheck.Gen in
  sized_size (int_range 0 2)
  @@ fix (fun self n ->
         match n with
         | 0 -> oneof [ map (fun k -> Obs.Konst (float_of_int k)) (int_range 50 150); return Obs.Spot ]
         | n ->
             oneof
               [
                 map2 (fun a b -> Obs.Sub (a, b)) (self (n - 1)) (self (n - 1));
                 map2 (fun a b -> Obs.Max (a, b)) (self (n - 1)) (self (n - 1));
                 map (fun k -> Obs.Konst (float_of_int k)) (int_range 0 2);
               ])

let bool_obs =
  let open QCheck.Gen in
  oneof
    [
      return Obs.Always;
      map (fun k -> Obs.Ge (Obs.Spot, Obs.Konst (float_of_int k))) (int_range 60 140);
      map (fun k -> Obs.Le (Obs.Spot, Obs.Konst (float_of_int k))) (int_range 60 140);
      map (fun d -> Obs.AtOrAfter (Date.add_days today (d * 30))) (int_range 1 12);
    ]

(* No Or and no Anytime: the property compares both interpreters, and Monte
   Carlo cannot price a holder choice. Those rules are covered by unit tests. *)
let contract =
  let open QCheck.Gen in
  sized_size (int_range 0 3)
  @@ fix (fun self n ->
         match n with
         | 0 -> oneof [ return Contract.Zero; return Contract.One ]
         | n ->
             oneof
               [
                 map (fun c -> Contract.Give c) (self (n - 1));
                 map2 (fun a b -> Contract.And (a, b)) (self (n - 1)) (self (n - 1));
                 map2 (fun o c -> Contract.Scale (o, c)) float_obs (self (n - 1));
                 map3 (fun o a b -> Contract.Cond (o, a, b)) bool_obs (self (n - 1)) (self (n - 1));
                 map2 (fun o c -> Contract.When (o, c)) bool_obs (self (n - 1));
                 map2 (fun o c -> Contract.Until (o, c)) bool_obs (self (n - 1));
               ])

let arbitrary_contract = QCheck.make contract ~print:Contract.to_string

let prop_price_preserved =
  QCheck.Test.make ~name:"simplify preserves the lattice price" ~count:300 arbitrary_contract
    (fun c ->
      let before = Lattice.price model c in
      let after = Lattice.price model (Simplify.simplify c) in
      Float.abs (before -. after) <= 1e-9 *. (1.0 +. Float.abs before))

let prop_simplify_is_idempotent =
  QCheck.Test.make ~name:"simplify is idempotent" ~count:300 arbitrary_contract (fun c ->
      let once = Simplify.simplify c in
      Simplify.simplify once = once)

let suite =
  List.map QCheck_alcotest.to_alcotest [ prop_price_preserved; prop_simplify_is_idempotent ]
```

Register `("simplify", Test_simplify.suite)` in `test/test_contract_lab.ml`, and add
`test_simplify` to the test executable's modules if dune needs it listed.

- [ ] **Step 2: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound module Simplify`.

- [ ] **Step 3: Implement the simplifier**

`lib/simplify.ml`:

```ocaml
open Contract

(* Structural equality is safe here: contracts and observables carry no
   functions and no cycles, because the observable algebra is a closed set of
   constructors. That was the reason for closing it. *)
let equal (a : t) (b : t) = a = b

let rec simplify (c : t) : t =
  match c with
  | Zero | One -> c
  | Give c -> (
      match simplify c with Zero -> Zero | Give inner -> inner | s -> Give s)
  | And (a, b) -> (
      match (simplify a, simplify b) with
      | Zero, s | s, Zero -> s
      | sa, sb -> And (sa, sb))
  | Or (a, b) -> (
      match (simplify a, simplify b) with
      | sa, sb when equal sa sb -> sa
      | sa, sb -> Or (sa, sb))
  | Cond (o, a, b) -> (
      match (simplify a, simplify b) with
      | sa, sb when equal sa sb -> sa
      | sa, sb -> Cond (o, sa, sb))
  | Scale (o, c) -> (
      match (o, simplify c) with
      | _, Zero -> Zero
      | Obs.Konst k, _ when k = 0.0 -> Zero
      | Obs.Konst k, s when k = 1.0 -> s
      | o, Scale (inner, s) -> simplify (Scale (Obs.Mul (o, inner), s))
      | o, s -> Scale (o, s))
  | When (o, c) -> ( match simplify c with Zero -> Zero | s -> When (o, s))
  | Anytime (o, c) -> ( match simplify c with Zero -> Zero | s -> Anytime (o, s))
  | Until (o, c) -> ( match simplify c with Zero -> Zero | s -> Until (o, s))
```

- [ ] **Step 4: Run to verify it passes**

Run: `dune test`
Expected: PASS. If `prop_price_preserved` fails, QCheck prints the shrunk contract that
broke it: that contract is a bug in a rewrite rule, and the rule comes out rather than the
test.

One rule that is deliberately absent, and worth being able to explain: `Until (o, Until
(o, c))` is not collapsed, and `When (o, When (o, c))` is not either, because the second
test is evaluated at the node the first one selected, not at the root.

- [ ] **Step 5: Commit**

```bash
git add lib/simplify.ml test
git commit -m "Add a price-preserving simplifier with properties"
```

---

### Task 11: The digital that is not N(d2)

**Files:**
- Create: `lib/svi.ml`, `lib/study.ml`, `data/svi_slice.txt`, `test/test_study.ml`
- Modify: `bin/main.ml`, `test/test_contract_lab.ml`

**Interfaces:**
- Produces:
  - `Svi.{slice, of_file, sigma, skew}` with `slice = { a; b; rho; m; s; t; forward }`
  - `Study.{digital_flat, digital_from_spread, skew_adjustment, table}`

The finance: a cash-or-nothing digital paying 1 is `exp(-rT) N(d2)` under a single
volatility. It is also the limit of a call spread, `-dC/dK`. With a smile, `C(K)` uses
`sigma(K)`, so

```
-dC/dK = exp(-rT) N(d2) - vega(K) * dsigma/dK
```

The second term is the skew correction, it has the sign of the smile's slope, and on a
crypto smile it is not small. `vol-lab` fits SVI slices; one slice is exported here as
seven numbers, and this task measures the correction across strikes.

- [ ] **Step 1: Export a slice from vol-lab**

In `vol-lab`, fit a slice and write its parameters to `~/code/contract-lab/data/svi_slice.txt`:

```
a 0.0400
b 0.1000
rho -0.3000
m 0.0000
s 0.1000
t 0.2500
forward 100.0000
```

Use the real fitted numbers, not these. Keep the file to seven `key value` lines so it
parses with `Scanf` and needs no JSON dependency. Record in the file's header comment
which `vol-lab` command produced it and on what date.

- [ ] **Step 2: Write the failing test**

`test/test_study.ml`:

```ocaml
open Contract_lab

let flat = { Svi.a = 0.04; b = 0.0; rho = 0.0; m = 0.0; s = 0.1; t = 1.0; forward = 100.0 }
let skewed = { flat with Svi.b = 0.1; rho = -0.3 }

let test_flat_slice_has_no_skew () =
  Alcotest.(check (float 1e-9)) "sigma is flat" (Svi.sigma flat ~strike:80.0)
    (Svi.sigma flat ~strike:120.0);
  Alcotest.(check (float 1e-6)) "skew is zero" 0.0 (Svi.skew flat ~strike:100.0)

let test_flat_slice_recovers_n_d2 () =
  let s = 100.0 and r = 0.0 in
  let spread = Study.digital_from_spread flat ~s ~r ~strike:100.0 in
  let closed = Study.digital_flat flat ~s ~r ~strike:100.0 in
  Alcotest.(check (float 1e-4)) "call spread equals N(d2)" closed spread

let test_the_skew_term_explains_the_difference () =
  let s = 100.0 and r = 0.0 in
  let strike = 95.0 in
  let spread = Study.digital_from_spread skewed ~s ~r ~strike in
  let closed = Study.digital_flat skewed ~s ~r ~strike in
  let adjustment = Study.skew_adjustment skewed ~s ~r ~strike in
  (* digital = N(d2) - vega * dsigma/dK, to the accuracy of the finite difference *)
  Alcotest.(check (float 1e-3)) "decomposition holds" (closed -. adjustment) spread;
  Alcotest.(check bool) "and it is not negligible" true
    (Float.abs (spread -. closed) > 1e-3)

let test_the_dsl_prices_the_same_digital () =
  let s = 100.0 and r = 0.0 in
  let strike = 95.0 in
  let expiry = Date.add_days (Date.of_ymd 2026 1 1) (int_of_float (skewed.Svi.t *. 365.0)) in
  let m =
    { Lattice.s0 = s; r; sigma = Svi.sigma skewed ~strike; today = Date.of_ymd 2026 1 1;
      horizon = expiry; steps = 2000 }
  in
  let dsl = Lattice.price m (Products.digital_call ~strike ~expiry ~cash:1.0) in
  let closed = Study.digital_flat skewed ~s ~r ~strike in
  Alcotest.(check bool) "lattice agrees with the flat-vol closed form" true
    (Float.abs (dsl -. closed) < 0.02)

let suite =
  [
    Alcotest.test_case "flat slice" `Quick test_flat_slice_has_no_skew;
    Alcotest.test_case "flat recovers N(d2)" `Quick test_flat_slice_recovers_n_d2;
    Alcotest.test_case "skew term" `Quick test_the_skew_term_explains_the_difference;
    Alcotest.test_case "dsl digital" `Quick test_the_dsl_prices_the_same_digital;
  ]
```

- [ ] **Step 3: Run to verify it fails**

Run: `dune test`
Expected: FAIL, `Unbound module Svi`.

- [ ] **Step 4: Implement SVI and the study**

`lib/svi.ml`:

```ocaml
(** A raw SVI slice: total variance w(k) = a + b (rho (k - m) + sqrt((k - m)^2 + s^2))
    in log-moneyness k = ln(K / F), for one expiry. *)
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
  sl.a +. (sl.b *. ((sl.rho *. (k -. sl.m)) +. sqrt (((k -. sl.m) ** 2.0) +. (sl.s ** 2.0))))

let sigma sl ~strike =
  let k = log (strike /. sl.forward) in
  sqrt (Float.max 1e-12 (total_variance sl k) /. sl.t)

(** dsigma/dK by central difference, one percent of the strike either side. *)
let skew sl ~strike =
  let h = 0.01 *. strike in
  (sigma sl ~strike:(strike +. h) -. sigma sl ~strike:(strike -. h)) /. (2.0 *. h)

let of_file path =
  let get key line = Scanf.sscanf line "%s %f" (fun k v -> if k = key then Some v else None) in
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
```

`lib/study.ml`:

```ocaml
(** The digital as the market would price it if one volatility applied: the
    Black-Scholes cash-or-nothing value at sigma(K). *)
let digital_flat sl ~s ~r ~strike =
  Bs.digital_call ~s ~k:strike ~r ~sigma:(Svi.sigma sl ~strike) ~t:sl.Svi.t ~cash:1.0

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
```

- [ ] **Step 5: Run to verify it passes**

Run: `dune test`
Expected: PASS, 4 cases.

- [ ] **Step 6: Wire the CLI**

`bin/main.ml`:

```ocaml
open Contract_lab

let expiry = Date.of_ymd 2027 1 1

let termsheet () =
  List.iter
    (fun (name, c) -> Printf.printf "%-22s %s\n" name (Contract.to_string c))
    [
      ("zero coupon bond", Products.zcb ~date:expiry ~amount:100.0);
      ("european call", Products.european_call ~strike:100.0 ~expiry);
      ("digital call", Products.digital_call ~strike:100.0 ~expiry ~cash:1.0);
      ("down and out call", Products.down_and_out_call ~strike:100.0 ~barrier:90.0 ~expiry);
      ("american put", Products.american_put ~strike:100.0);
      ( "autocallable",
        Products.autocallable
          ~observations:[ Date.of_ymd 2026 12 25; Date.of_ymd 2027 3 25; Date.of_ymd 2027 6 25 ]
          ~trigger:100.0 ~coupon:5.0 ~notional:100.0 ~ki_barrier:60.0 );
    ]

let study path =
  let sl = Svi.of_file path in
  Printf.printf "strike   N(d2)     call spread   difference (bps)\n";
  List.iter
    (fun (k, flat, spread, bps) -> Printf.printf "%-8.1f %-9.5f %-13.5f %+.1f\n" k flat spread bps)
    (Study.table sl ~s:sl.Svi.forward ~r:0.0
       ~strikes:[ 80.0; 90.0; 95.0; 100.0; 105.0; 110.0; 120.0 ])

let () =
  match Sys.argv with
  | [| _; "termsheet" |] -> termsheet ()
  | [| _; "study" |] -> study "data/svi_slice.txt"
  | [| _; "study"; path |] -> study path
  | _ -> print_endline "usage: main (termsheet | study [slice-file])"
```

- [ ] **Step 7: Run it**

```bash
dune exec bin/main.exe -- termsheet
dune exec bin/main.exe -- study
```

Expected: the term sheets print, and the study prints a table whose last column is the
headline number of the repository.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Measure the skew correction to a digital"
```

---

### Task 12: README and limits

**Files:**
- Modify: `README.md`, `docs/notes.md`

- [ ] **Step 1: Write the README**

```markdown
# contract-lab

A derivative is not a product, it is an expression.

    let down_and_out_call ~strike ~barrier ~expiry =
      Until (Le (Spot, Konst barrier), european_call ~strike ~expiry)

Ten combinators after Peyton Jones, Eber and Seward, observables typed by a GADT, and two
interpreters of the same algebra: a CRR lattice where `when`, `anytime` and `until` are
discounting, the Snell envelope and absorption, and a Monte Carlo that refuses any
contract containing a choice instead of guessing at it.

**Headline.** On an SVI slice fitted to a real BTC smile, a cash-or-nothing digital priced
as the limit of a call spread differs from `exp(-rT) N(d2)` by X basis points of the payout
at the 95 strike, and the difference is exactly `vega * dsigma/dK` to three decimals. The
test that pins that identity is `test_the_skew_term_explains_the_difference`.

## Try it

    opam switch create . 5.4.1
    opam install -y --deps-only --with-test .
    dune test
    dune exec bin/main.exe -- termsheet
    dune exec bin/main.exe -- study

## Design notes

- **Why a GADT, and why a closed set of observables.** [one paragraph, from Task 3]
- **Why absorption is not pointwise.** [one paragraph, from docs/notes.md]
- **Why Monte Carlo refuses `anytime`.** [one paragraph: a forward simulation cannot see
  the holder's optimal decision; least-squares Monte Carlo would, and is not here]

## What this does not do

- One currency. `One` is one unit of the numeraire; multi-currency needs FX observables.
- ACT/365 and no holiday calendar. Real term sheets settle on business days.
- Continuous barriers are priced on a discretely monitored tree, aligned to the barrier
  after Boyle and Lau (1994). The remaining error is quantified in the test, not waved at.
- No credit, no collateral, no multi-asset payoffs.
- The SVI slice is a fit exported from `vol-lab`, not a live surface.

## References

Peyton Jones, Eber, Seward, "Composing contracts" (ICFP 2000). Peyton Jones and Eber,
"How to write a financial contract" (2003). Reiner and Rubinstein, "Breaking down the
barriers" (Risk, 1991). Boyle and Lau (1994). Bahr, Berthold and Elsman (ICFP 2015) on
certified contract management.
```

- [ ] **Step 2: Fill in X from the study output**

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Write up the algebra and the digital result"
```

---

## Self-review

Checked against `docs/spec.md`:

- Combinator algebra with typed observables: Tasks 3 and 4.
- Term-sheet printer: Task 4, pinned by expect tests.
- Lattice interpreter with the three backward operators: Task 6, with early exercise in
  Task 7 and absorption in Task 8.
- Monte Carlo on the choice-free subset with a static check: Task 9.
- Simplifier with a price-preserving property: Task 10.
- The digital study: Task 11.
- Every validation row of the spec's table has a test: parity and 10.4506 in Task 5,
  barrier-to-zero in Tasks 5 and 8, American call identity in Task 7, lattice against
  Monte Carlo in Task 9, QCheck in Task 10.

Open items an executor must not silently skip:

1. Task 11 step 1 needs real SVI parameters exported from `vol-lab`. Shipping the example
   numbers as if they were fitted would be exactly the overclaiming this repo is meant to
   avoid.
2. The expect tests in Tasks 2, 4, 5 and 6 are promoted, not written by hand. Read each
   promoted value before committing it; a promoted wrong answer is a test that can never
   fail.
3. If `Or` or `Anytime` gain rewrite rules in `Simplify`, the QCheck generator must stay
   choice-free, and those rules need their own lattice-only property test.
