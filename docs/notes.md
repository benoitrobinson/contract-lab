# Notes

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
