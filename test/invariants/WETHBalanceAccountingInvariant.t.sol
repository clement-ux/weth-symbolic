// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base} from "../Base.t.sol";

contract WETHBalanceAccountingInvariant is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                        ✦✦✦ BALANCE ACCOUNTING CHECKLIST ✦✦✦                              ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  CLOSED TWO-HOLDER MODEL                                                                 ║
    // ║  ├─ [x] balanceOf(alice) <= totalSupply                                                  ║
    // ║  ├─ [x] balanceOf(bobby) <= totalSupply                                                  ║
    // ║  └─ [x] totalSupply == balanceOf(alice) + balanceOf(bobby)                               ║
    // ║                                                                                          ║
    // ║  GLOBAL MODEL                                                                            ║
    // ║  ├─ [ ] forall user: balanceOf(user) <= totalSupply                                      ║
    // ║  └─ [ ] totalSupply == ghostSumOfAllBalances (requires mapping-aware SSTORE hook)        ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    function setUp() public override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.handler_deposit.selector;
        selectors[1] = this.handler_withdraw.selector;
        selectors[2] = this.handler_transfer.selector;

        uint256 seedBalance = type(uint128).max;

        // Construct a closed, reachable two-holder state large enough for every
        // uint96 debit through depth 2, then restore both actors' deposit funding.
        vm.deal(alice, seedBalance);
        vm.prank(alice);
        weth.deposit{value: seedBalance}();
        vm.deal(alice, seedBalance);

        vm.deal(bobby, seedBalance);
        vm.prank(bobby);
        weth.deposit{value: seedBalance}();
        vm.deal(bobby, seedBalance);

        // The outer sender only invokes the handlers. Each handler fixes the
        // protocol-level actor with vm.prank to avoid a sender/selector cross product.
        targetSender(deployer);
        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function handler_deposit(uint96 amount) public {
        vm.prank(alice);
        weth.deposit{value: amount}();
    }

    function handler_withdraw(uint96 amount) public {
        vm.prank(bobby);
        weth.withdraw(amount);
    }

    function handler_transfer(uint96 amount) public {
        vm.prank(alice);
        assertTrue(weth.transfer(bobby, amount));
    }

    /// @dev This campaign quantifies over a closed set of two distinct holders: Alice and Bobby.
    /// Both start with type(uint128).max ETH and WETH, so every uint96 handler call succeeds through
    /// depth 4. Alice deposits and transfers to Bobby; Bobby withdraws. The reverse direction, aliases,
    /// arbitrary addresses, receive(), transferFrom(), finite allowances, and expected reverts belong in
    /// dedicated stateless rules. approve() is omitted because it cannot affect balances or totalSupply.
    /// @dev A mapping-aware SSTORE hook could replace this finite-holder sum with a revert-aware ghost updated
    /// on every balanceOf write, covering every address touched by the bounded campaign. An SLOAD hook alone
    /// cannot enumerate all mapping keys or maintain that global sum.
    /// @dev With H = 3 and S = 1, depth 2 covers at most 9 complete schedules and 12 non-empty prefixes before
    /// executor-level path splitting. The measured PASS explored 72 paths and 139 queries in 2,074 ms.
    /// @dev With H = 3 and S = 1, depth 3 covers at most 27 complete schedules and 39 non-empty prefixes before
    /// executor-level path splitting. The measured PASS explored 234 paths and 462 queries in 25,054 ms.
    /// @dev With H = 3 and S = 1, depth 4 covers at most 81 complete schedules and 120 non-empty prefixes before
    /// executor-level path splitting. The measured PASS explored 720 paths and 1,443 queries in 193,717 ms.
    ///
    /// forge-config: default.symbolic.invariant_depth = 4
    /// forge-config: default.symbolic.timeout = 300
    /// forge-config: default.symbolic.max_paths = 4096
    /// forge-config: default.symbolic.max_solver_queries = 10000
    function invariant_balanceAccounting() public view {
        uint256 supply = weth.totalSupply();
        uint256 aliceBalance = weth.balanceOf(alice);
        uint256 bobbyBalance = weth.balanceOf(bobby);

        assertLe(aliceBalance, supply, "Alice balance exceeds totalSupply");
        assertLe(bobbyBalance, supply, "Bobby balance exceeds totalSupply");
        assertEq(aliceBalance + bobbyBalance, supply, "known balances != totalSupply");
    }
}
