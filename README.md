# WETH Symbolic Verification

Bounded symbolic verification of a minimalist WETH implementation using the
experimental `foundry-evm-symbolic` backend.

The suite combines stateless `check*` rules with small stateful `invariant*`
campaigns. A `PASS` applies only to the modeled state and configured bounds; it
is not an unbounded proof.

## Setup

The required Foundry build is pinned in `.foundry-version`. Z3 and `jq` must be
available on `PATH`.

```sh
make foundry
make check-foundry
git submodule update --init --recursive
forge build
```

## Run

```sh
# Complete symbolic suite with compact output
make symbolic

# One rule or invariant
make symbolic MATCH='^check_deposit$'
make symbolic MATCH='^invariant_solvency$'

# Raw Forge output for one contract
forge test --symbolic --match-contract WETHSymbolic_Rules
forge test --symbolic --match-contract WETHBalanceAccountingInvariant

# Additional Forge arguments
make symbolic MATCH='^invariant_balanceAccounting$' SYMBOLIC_ARGS='-vv'

# CI-friendly output
COLOR=0 make symbolic
```

The summary command exits non-zero for both counterexamples and incomplete
results. A counterexample is actionable only when its concrete replay is
confirmed.

## Layout

```text
src/WETH.sol
test/Base.t.sol
test/rules/WETHRules.t.sol
test/invariants/WETHBalanceAccountingInvariant.t.sol
test/invariants/WETHSolvencyInvariant.t.sol
test/invariants/WETHUserWealthInvariant.t.sol
test/invariants/WETHClosedEthConservationInvariant.t.sol
```

The property checklist, assumptions, fixed roles, omitted transitions, and
campaign bounds are documented directly in each test file.

## Model

- `setUp()` runs concretely before symbolic exploration.
- `check*` rules verify a single transition or short fixed sequence with
  symbolic arguments.
- `invariant*` campaigns check every explored prefix of a bounded handler
  sequence.
- Ordinary stateful fuzzing is disabled in `foundry.toml` to keep its output
  separate from symbolic invariant results.
- Repository defaults live in `[profile.default.symbolic]`; inline
  `forge-config` annotations override them per campaign.

## Verified properties

All results are bounded by the current symbolic model and configuration.

| Layer | Verified property |
| --- | --- |
| Rule | `deposit` and `receive` increase user WETH, supply, and reserve by the deposited amount. |
| Rule | `withdraw` burns and returns ETH one-for-one; a round-trip restores the initial ETH balance. |
| Rule | `transfer` preserves supply, reserve, self-transfer accounting, and unrelated balances. |
| Rule | `approve` sets allowances; `transferFrom` decreases finite allowances and preserves infinite ones. |
| Rule | Invalid `withdraw`, `transfer`, and `transferFrom` calls revert atomically; failed ETH delivery also rolls back. |
| Rule | Forced ETH breaks `reserve == totalSupply` but preserves `reserve >= totalSupply`. |
| Invariant | `balanceOf(alice) + balanceOf(bobby) == totalSupply` in the closed two-holder model. |
| Invariant | `address(weth).balance >= totalSupply`, including a forced-ETH surplus. |
| Invariant | `alice.balance + balanceOf(alice) == initialUserWealth` for deposit/withdraw sequences. |
| Invariant | `address(weth).balance + alice.balance + bobby.balance == initialTotalEth` in the closed model. |

Stateful relations are checked after every explored prefix up to depth 4. Exact
actors, exclusions, and measured bounds are documented in the test files.

## Limitations

- Stateful accounting campaigns use fixed, finite actor sets.
- A mapping-aware storage hook is still required to maintain a Certora-style
  ghost sum over every ERC-20 holder.
- Arbitrary symbolic mapping keys can produce non-replayable counterexamples;
  affected rules use fixed roles while keeping amounts symbolic.
- Success-only handlers use reachable prefunding. Revert and atomicity behavior
  is covered by dedicated stateless rules.
- Forced ETH uses `SELFDESTRUCT` only for its transfer semantics.

## References

- [Certora `ERC20Full.spec`](https://github.com/Certora/Examples/blob/279e55370f969607c922e9eb3089c82911b76a20/DEFI/ERC20/certora/specs/ERC20Full.spec)
- [Origin Protocol OUSD specs](https://github.com/OriginProtocol/origin-dollar/tree/d2480092a06ebb116d2ce83d94ae318c6168a0d7/certora/specs/OUSD)

These are design references for property decomposition and ghost accounting;
the Foundry suite does not claim equivalent coverage.
