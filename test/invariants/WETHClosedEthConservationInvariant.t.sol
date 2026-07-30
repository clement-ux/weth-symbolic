// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base} from "../Base.t.sol";

contract WETHClosedEthConservationInvariant is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                      ✦✦✦ CLOSED ETH CONSERVATION CHECKLIST ✦✦✦                           ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  CLOSED WETH / ALICE / BOBBY MODEL                                                       ║
    // ║  └─ [x] WETH reserve + Alice ETH + Bobby ETH remains constant                            ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    uint256 internal initialTotalEth;

    function setUp() public override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.handler_depositAlice.selector;
        selectors[1] = this.handler_withdrawBobby.selector;

        uint256 seedBalance = type(uint128).max;

        // Alice funds deposits. Bobby receives reachable WETH for withdrawals,
        // then has his ETH restored before the conserved total is recorded.
        vm.deal(alice, seedBalance);
        vm.deal(bobby, seedBalance);
        vm.prank(bobby);
        weth.deposit{value: seedBalance}();
        vm.deal(bobby, seedBalance);

        initialTotalEth = address(weth).balance + alice.balance + bobby.balance;

        // The outer sender has no protocol meaning; handlers fix the actual actors.
        targetSender(deployer);
        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function handler_depositAlice(uint96 amount) public {
        vm.prank(alice);
        weth.deposit{value: amount}();
    }

    function handler_withdrawBobby(uint96 amount) public {
        vm.prank(bobby);
        weth.withdraw(amount);
    }

    /// @dev This is a closed ETH system containing only WETH, Alice, and Bobby. Alice starts with
    /// type(uint128).max ETH; Bobby starts with type(uint128).max ETH and WETH, so every uint96 deposit or
    /// withdrawal succeeds through depth 4. Alice deposits and Bobby withdraws; the reverse actor roles are
    /// omitted because the same address-independent transitions are covered by arbitrary-user stateless rules.
    /// receive() duplicates deposit(). ERC-20 transfers and approvals are omitted because they cannot affect any
    /// ETH term in this property. Forced ETH, outside ETH transfers, contract recipients, and expected reverts are
    /// excluded from this closed campaign and belong in dedicated rules or campaigns.
    /// With H = 2 and S = 1, depth 4 covers at most 16 complete schedules and 30 non-empty prefixes before
    /// executor-level path splitting.
    ///
    /// forge-config: default.symbolic.invariant_depth = 4
    /// forge-config: default.symbolic.timeout = 300
    /// forge-config: default.symbolic.max_paths = 4096
    /// forge-config: default.symbolic.max_solver_queries = 10000
    function invariant_closedEthConservation() public view {
        uint256 currentTotalEth = address(weth).balance + alice.balance + bobby.balance;

        assertEq(currentTotalEth, initialTotalEth, "closed ETH total changed");
    }
}
