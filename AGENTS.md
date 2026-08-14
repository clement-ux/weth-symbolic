# Foundry Symbolic EVM Project Guide

## Purpose

This repository exercises `foundry-evm-symbolic` against WETH. Forge deploys
contracts and runs `setUp()` concretely, explores symbolic inputs or bounded
call sequences, then concretely replays candidate counterexamples.

Treat every result as bounded verification and counterexample finding, not as
an unconditional proof.

## External verification references

Use the following Certora specifications as the primary design references for
ERC-20 accounting work. They are references for property decomposition and
ghost design, not authority to copy assumptions or claim equivalent coverage.

- [`Certora/Examples` `ERC20Full.spec`](https://github.com/Certora/Examples/blob/279e55370f969607c922e9eb3089c82911b76a20/DEFI/ERC20/certora/specs/ERC20Full.spec)
  is the closest reference for WETH. It tracks the sum of all balances with a
  `mathint` ghost updated by an `Sstore` hook and checks equality with
  `totalSupply`. It also separates global conservation from recipient,
  third-party, alias, allowance, authorization, revert, and overflow rules.
- [`OriginProtocol/origin-dollar` OUSD specs](https://github.com/OriginProtocol/origin-dollar/tree/d2480092a06ebb116d2ce83d94ae318c6168a0d7/certora/specs/OUSD)
  are the reference for more complex accounting. In particular, inspect
  `BalanceInvariants.spec`, `SumOfBalances.spec`, `AccountInvariants.spec`, and
  `OtherInvariants.spec`. They split rebasing and non-rebasing accounting,
  mirror storage with ghosts and hooks, define effective balances for delegated
  accounts, and use inequalities or tolerances where rounding prevents exact
  equality.

For ordinary non-rebasing WETH accounting, start from the `ERC20Full.spec`
model. Use the OUSD model when a property needs multiple accounting domains,
derived balances, linked account identities, rounding, or interdependent
invariants.

CVL `Sstore`/`Sload` hooks and unbounded mapping sums do not translate directly
to Foundry symbolic tests. Adapt them with finite-role ghosts and targeted
stateless rules, and state the resulting under-approximation. Audit every
`require`, `preserved`, filter, fixed symbolic value, and timeout workaround in
the reference specs before adopting the same restriction. Keep reference links
pinned to upstream commits and update them intentionally when adopting newer
behavior.

## Working rules

- Inspect `foundry.toml`, `src/WETH.sol`, `test/Base.t.sol`, and the relevant
  test before changing bounds or test structure.
- Keep changes small and preserve the exact property being tested.
- Ensure the invariant name, comments, assertion, and failure message describe
  the same relation (`>=` and `==` are different properties).
- Iterate with the smallest relevant symbolic test, then build and run the
  relevant wider suite.
- Never call `Incomplete` a pass.
- Report a `PASS` with its effective depth, path limit, query limit, and timeout.
- Accept a bug-finding `FAIL` only when its counterexample replay is confirmed.
- Do not delete replay artifacts merely to make a run appear clean.
- Explicitly document finite users, fixed roles, omitted transitions, excluded
  reverts, and unsupported EVM or cheatcode behavior.

## Test architecture

Use two complementary layers:

- Stateless `check*` rules verify one transition or a short fixed sequence with
  symbolic values and, where concrete replay is reliable, symbolic addresses.
- Stateful `invariant*` campaigns verify a structural property after every
  prefix of a bounded, deliberately small transition system.

Use stateless rules for arbitrary addresses, alias cases, finite allowances,
revert/atomicity behavior, and actor combinations excluded from a stateful
campaign. When symbolic mapping keys produce non-replayable counterexamples,
use a small set of fixed roles, keep the relevant values symbolic, and document
the resulting address under-approximation. Do not expect a stateful campaign to
maximize combinations like stateful fuzzing.

Keep each invariant campaign in its own contract, normally in its own file,
when it needs different handlers, senders, initial state, or symbolic bounds.
Keep only shared deployment, address definitions, and reusable helper contracts
in `test/Base.t.sol`. Campaign-specific state belongs in that campaign's
`setUp()`, never inside the invariant function.

Current layout:

```text
test/Base.t.sol
test/rules/WETHRules.t.sol
test/invariants/WETHSolvencyInvariant.t.sol
test/invariants/WETHBalanceAccountingInvariant.t.sol
test/invariants/WETHUserWealthInvariant.t.sol
test/invariants/WETHClosedEthConservationInvariant.t.sol
```

## Stateless symbolic rules

Functions beginning with `check` or `prove` are discovered in symbolic mode.
Their ABI arguments become symbolic calldata.

```solidity
function check_property(uint256 amount, address user) external {
    vm.assume(user != address(0));
    // Construct a reachable pre-state, execute one transition, assert deltas.
}
```

- `require` and `vm.assume` prune infeasible paths.
- Assertions are properties the engine attempts to disprove.
- Ordinary user reverts terminate the current path.
- If every explored path reverts, the result is `RevertAll`, not a proof.
- Prefer reachable setup and concrete, replayable failure conditions.
- For revert atomicity, capture the expected revert, assert that the call
  failed, and compare every affected storage and ETH term with its snapshot.
- Bound dynamic calldata lengths explicitly when the property depends on them.

## Stateful symbolic invariants

Functions beginning with `invariant` or `statefulFuzz` use bounded symbolic call
sequences. State persists symbolically between handler calls, and the invariant
is checked after every explored prefix.

`symbolic.invariant_depth` is the maximum number of target calls in a sequence.
It does not need to equal the number of handlers. Depth 3 explores sequences of
up to three calls whether the campaign exposes two handlers or five; it cannot
establish safety for violations requiring a fourth call.

### Handler design

Target the harness and use one concrete outer `targetSender` when the outer
caller has no protocol meaning. Set the actual protocol actor with `vm.prank`
inside each handler.

```solidity
targetSender(deployer);
targetContract(address(this));

function handler_transfer(uint96 amount) public {
    vm.prank(alice);
    weth.transfer(bobby, amount);
}
```

This removes an irrelevant sender/selector cross product. Fixed Alice/Bobby/
Carol roles are nevertheless an under-approximation and should be complemented
by arbitrary-address and alias-focused stateless rules when those symbolic
mapping accesses replay reliably. Otherwise use explicit fixed-role partitions
and document the omitted aliases.

Each campaign must document:

- its finite holder/role set and excluded aliases;
- seeded ETH, WETH, and allowances;
- omitted handlers and why they cannot affect the property;
- assumptions or prefunding used to exclude expected reverts;
- its inline depth, path limit, query limit, and timeout.

Do not enable `fail_on_revert` globally merely to reduce exploration. Model
important failure behavior in dedicated rules. Success-only handlers may use a
clear precondition or reachable prefunding, but must document the excluded
domain.

### Accounting properties and ghosts

Use `registerMappingSstoreHook` on the balance mapping root to maintain a
revert-aware sum across every holder touched by a campaign. Register the hook
before setup writes, authenticate callbacks with `msg.sender == address(vm)`,
and use `symbolic.storage_layout = "zero_init"` when a freshly deployed
contract and a zero-valued ghost model unwritten mapping entries as zero.

The aggregate proves conservation but not recipient correctness. When recipient
correctness matters, maintain expected per-account ghost balances according to
the specification in each successful handler, then compare the relevant actual
balances against those ghosts. Keep arbitrary-address and alias behavior in
stateless rules until symbolic stateful replay is reliable for those roles.

Do not use `vm.setArbitraryStorage` on WETH for reachable-state accounting
invariants. Arbitrary target storage may violate ERC-20 relationships and create
unreachable states. Reserve it for external dependencies whose arbitrary
environment state is intentionally part of the model.

## Path growth and tuning

With `H` eligible selectors, `S` outer target senders, and depth `D`, estimate
the scheduler branching with:

```text
B = H * S
complete schedules at depth D = B^D
non-empty prefixes through D = B + B^2 + ... + B^D
```

These are not executor path counts. Symbolic arguments, Solidity branches,
reverts, assumptions, calls, and assertions can split each schedule into more
paths and solver queries.

Measured balance-accounting results:

| Depth | Complete schedules | Prefixes | Executor paths | Solver queries | Solver time |
|------:|-------------------:|---------:|---------------:|---------------:|------------:|
| 2 | 9 | 12 | 72 | 170 | 7.517 s |
| 3 | 27 | 39 | 234 | 594 | 193.703 s |

This campaign has `H = 3`, `S = 1`, and symbolic actor arguments for deposit,
withdraw, and transfer. Both rows are measured `PASS` results; depth 4 has not
yet been measured for this model. Runtime does not scale linearly, and future
backend or test changes can invalidate these measurements.

Before raising bounds:

1. Remove selectors that cannot affect the property.
2. Remove irrelevant outer senders and fix protocol roles inside handlers.
3. Preconstruct reachable success states instead of exploring routine reverts.
4. Move single-transition, alias, and revert coverage to stateless rules.
5. Split campaigns by property when their useful transitions or bounds differ.

Raise `max_paths` for a path-limit failure, `max_solver_queries` for a query
limit, and `timeout` for a timeout. More paths do not fix a timeout. Reducing an
argument from `uint96` to `uint24` can shrink SMT expressions, but usually does
not reduce path count unless it changes branch feasibility.

## Configuration

Keep repository defaults in `foundry.toml` and campaign-specific bounds in
inline `forge-config:` annotations.

```solidity
/// forge-config: default.symbolic.invariant_depth = 3
/// forge-config: default.symbolic.timeout = 300
/// forge-config: default.symbolic.max_paths = 4096
```

Inline values take precedence over CLI overrides. Inspect the test source when
`--symbolic-invariant-depth` or another override appears to have no effect.

The repository sets ordinary invariant `runs = 0` and `depth = 0` to suppress
classic stateful fuzz output. Symbolic invariant exploration instead uses
`[profile.default.symbolic]` and inline symbolic bounds.

The default solver is Z3. Other supported solvers may be tested, but compare
measured results before keeping a solver portfolio. Increasing CPU helps mainly
when independent tests or multiple solvers run concurrently; one difficult SMT
query is commonly limited by solver behavior rather than core count.

## Commands

```sh
forge build
forge test --symbolic
forge test --symbolic --match-test check_deposit
forge test --symbolic --match-contract WETHBalanceAccountingInvariant

make symbolic MATCH=invariant_balanceAccounting
make symbolic MATCH=invariant
```

The `make symbolic` target consumes Forge JSON and shows only symbolic results.
It exits non-zero for every non-`PASS` result, including `Incomplete` and
candidate counterexamples whose replay is not confirmed. Treat a failure as a
bug only when replay is confirmed. Pass extra Forge options through
`SYMBOLIC_ARGS`; disable colors with `COLOR=0`.

Always keep `--symbolic` explicit in documentation and reproducible commands.
Use `--match-test` for function names and `--match-contract` for contracts.

## Result interpretation

- `pass`: all paths explored within the effective model and bounds completed
  without a feasible failure.
- `fail_counterexample`: a failure was found; require
  `symbolic.replay.status == "confirmed"`.
- `incomplete`: the property was not established.

Common incomplete causes:

- `Stuck`: unsupported behavior or path/depth/query bound.
- `RevertAll`: every explored path reverted.
- `Timeout`: symbolic execution or solver timeout/unknown.
- `Error`: backend, ABI, bytecode, or solver failure.

Use the stable `.symbolic` JSON object. Relevant diagnostics include paths,
solver queries, solver time, SMT input bytes, largest query size, and maximum
query time. More SMT bytes do not imply more paths; they measure formula size.

## Model limitations

A `PASS` is limited by depth, paths, solver queries, timeout, calldata/loop
bounds, modeled accounts, and supported EVM behavior. Also remember:

- gas is not a proof resource;
- symbolic external-call targets cover known candidates, not arbitrary code;
- dynamic memory/copy sizes must remain provably bounded;
- fork mutation, symbolic creation, precompiles, and some cheatcodes are
  restricted;
- symbolic hashes assume modeled collision/preimage resistance;
- arbitrary or symbolic mapping keys can cause replay mismatches;
- unsupported behavior must produce `Incomplete`, never an assumed success.

Document any limitation relevant to the property being reported.

## Validation checklist

After changing Solidity contracts or symbolic tests:

1. Run `forge fmt --check`.
2. Run `forge build`.
3. Run the smallest relevant test explicitly with `--symbolic`.
4. For `FAIL`, confirm the concrete replay has the intended shape.
5. For `PASS`, confirm there is no incomplete result and report the bounds.
6. Run the broader relevant symbolic suite.
