// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base, ForceEther} from "../Base.t.sol";

contract WETHSolvencyInvariant is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                            ✦✦✦ SOLVENCY CHECKLIST ✦✦✦                                    ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  CORE INVARIANTS                                                                         ║
    // ║  ├─ [x] reserve >= totalSupply, including a state with forced ETH                        ║
    // ║  └─ [ ] ghostDeposits - ghostWithdrawals == totalSupply                                  ║
    // ║                                                                                          ║
    // ║  CLOSED-MODEL INVARIANTS                                                                 ║
    // ║  └─ [ ] reserve == totalSupply when forced ETH is excluded                               ║
    // ║                                                                                          ║
    // ║  EXPECTED COUNTEREXAMPLE                                                                 ║
    // ║  └─ [x] forced ETH breaks equality without breaking solvency                             ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    uint256 internal constant FORCED_ETH = 1 ether;

    function setUp() public override {
        super.setUp();

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.handler_deposit.selector;
        selectors[1] = this.handler_withdraw.selector;

        uint256 seedBalance = type(uint128).max;

        // Construct a reachable supply and preserve enough ETH and WETH for
        // every uint96 handler call to succeed through depth 4.
        vm.deal(alice, seedBalance);
        vm.prank(alice);
        weth.deposit{value: seedBalance}();
        vm.deal(alice, seedBalance);

        // Model a reachable strict surplus: SELFDESTRUCT transfers ETH without
        // calling receive(), so totalSupply is unchanged.
        ForceEther forceEther = new ForceEther();
        vm.deal(address(forceEther), FORCED_ETH);
        forceEther.forceSend(payable(address(weth)));

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

    /// @dev This campaign has one fixed actor, Alice, seeded with type(uint128).max ETH and WETH. A one-ether
    /// surplus is forced into WETH during concrete setup, so the initial relation is reserve > totalSupply.
    /// Deposit and withdraw are the only targeted transitions and every uint96 call succeeds through depth 4.
    /// receive() duplicates deposit(); ERC-20 transfers and approvals cannot affect reserve or totalSupply.
    /// Repeated force-sends are omitted because they can only increase the reserve; the dedicated forced-ETH rule
    /// demonstrates that equality is broken while this inequality remains true. Expected reverts and arbitrary
    /// users remain covered by stateless rules.
    /// With H = 2 and S = 1, depth 4 covers at most 16 complete schedules and 30 non-empty prefixes before
    /// executor-level path splitting.
    ///
    /// forge-config: default.symbolic.invariant_depth = 4
    /// forge-config: default.symbolic.timeout = 300
    /// forge-config: default.symbolic.max_paths = 4096
    /// forge-config: default.symbolic.max_solver_queries = 10000
    function invariant_solvency() public view {
        assertGe(address(weth).balance, weth.totalSupply(), "WETH reserve below totalSupply");
    }
}
