// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base} from "../Base.t.sol";

contract WETHUserWealthInvariant is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ USER WEALTH CHECKLIST ✦✦✦                                  ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  DEPOSIT / WITHDRAW CLOSED MODEL                                                         ║
    // ║  ├─ [x] Alice's ETH + WETH balance remains constant                                     ║
    // ║  └─ [ ] Generalize the stateful campaign to an arbitrary user                            ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    uint256 internal initialUserWealth;

    function setUp() public override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.handler_deposit.selector;
        selectors[1] = this.handler_withdraw.selector;

        uint256 seedBalance = type(uint128).max;

        // Give Alice enough reachable ETH and WETH for every uint96 deposit or
        // withdrawal to succeed through depth 4.
        vm.deal(alice, seedBalance);
        vm.prank(alice);
        weth.deposit{value: seedBalance}();
        vm.deal(alice, seedBalance);

        initialUserWealth = alice.balance + weth.balanceOf(alice);

        // The outer sender has no protocol meaning; handlers fix Alice as the actor.
        targetSender(deployer);
        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function handler_deposit(uint96 amount) public {
        vm.prank(alice);
        weth.deposit{value: amount}();
    }

    function handler_withdraw(uint96 amount) public {
        vm.prank(alice);
        weth.withdraw(amount);
    }

    /// @dev This is a closed one-user campaign with Alice as the only protocol actor. Alice starts with
    /// type(uint128).max ETH and WETH, excluding insufficient-funds and insufficient-balance reverts for every
    /// uint96 call through depth 4. Only deposit and withdraw are targeted because they exchange Alice's ETH and
    /// WETH one-for-one. Transfers, transferFrom, forced ETH, and external ETH flows are excluded because they can
    /// change Alice's individual wealth; receive() duplicates deposit(), while approve() cannot affect the property.
    /// Arbitrary users and the excluded transitions remain covered by dedicated stateless rules where applicable.
    /// With H = 2 and S = 1, depth 4 covers at most 16 complete schedules and 30 non-empty prefixes before
    /// executor-level path splitting.
    ///
    /// forge-config: default.symbolic.invariant_depth = 4
    /// forge-config: default.symbolic.timeout = 60
    /// forge-config: default.symbolic.max_paths = 4096
    /// forge-config: default.symbolic.max_solver_queries = 10000
    function invariant_userWealthConservation() public view {
        uint256 currentUserWealth = alice.balance + weth.balanceOf(alice);

        assertEq(currentUserWealth, initialUserWealth, "Alice ETH + WETH wealth changed");
    }
}
