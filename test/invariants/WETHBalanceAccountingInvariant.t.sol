// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base} from "../Base.t.sol";

interface IMappingStorageHookVm {
    function registerMappingSstoreHook(address target, bytes32 rootSlot, bytes4 callback) external;
}

contract WETHBalanceAccountingInvariant is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                        ✦✦✦ BALANCE ACCOUNTING CHECKLIST ✦✦✦                              ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  GLOBAL MODEL                                                                            ║
    // ║  └─ [x] totalSupply == ghostSumOfAllBalances                                             ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    IMappingStorageHookVm internal constant HOOK_VM =
        IMappingStorageHookVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant BALANCE_OF_ROOT_SLOT = bytes32(uint256(3));

    uint256 internal ghostSumOfAllBalances;

    function setUp() public override {
        super.setUp();

        HOOK_VM.registerMappingSstoreHook(address(weth), BALANCE_OF_ROOT_SLOT, this.onBalanceStore.selector);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.handler_deposit.selector;
        selectors[1] = this.handler_withdraw.selector;
        selectors[2] = this.handler_transfer.selector;

        // The outer sender only invokes handlers; each protocol actor is a
        // symbolic handler argument applied with vm.prank.
        targetSender(deployer);
        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function handler_deposit(address user, uint96 amount) public {
        vm.assume(user != address(0) && user != address(weth));

        vm.deal(user, amount);
        vm.prank(user);
        weth.deposit{value: amount}();
    }

    function handler_withdraw(address user, uint96 amount) public {
        vm.assume(user != address(0) && user != address(weth));
        vm.assume(amount <= weth.balanceOf(user));

        vm.prank(user);
        weth.withdraw(amount);
    }

    function handler_transfer(address from, address to, uint96 amount) public {
        vm.assume(from != address(0) && from != address(weth));
        vm.assume(amount <= weth.balanceOf(from));

        vm.prank(from);
        assertTrue(weth.transfer(to, amount));
    }

    /// @notice Checks that totalSupply equals the sum of every WETH balance touched by the symbolic campaign.
    /// @dev WETH starts freshly deployed with no seeded ETH, WETH, or allowances. The mapping SSTORE hook is
    /// registered before any balance write and maintains a revert-aware ghost sum from old and new balance values.
    /// zero_init is sound for this fresh deployment and makes every previously unwritten symbolic balance start at
    /// zero. The aggregate proves global conservation, not correct recipient attribution; dedicated stateless rules
    /// verify the per-account effects of transfer, mint, burn, and reverted operations.
    /// @dev Deposit and withdraw quantify over arbitrary nonzero users other than WETH; deposit gives its actor the
    /// exact ETH required for the call. Transfer quantifies over an arbitrary nonzero sender other than WETH and an
    /// unrestricted recipient, covering distinct users, aliases, self-transfers, WETH, and the zero address. Debit
    /// handlers assume sufficient WETH so this campaign explores successful accounting transitions. Expected
    /// reverts remain covered by stateless rules. receive() and transferFrom() are omitted because their balance
    /// effects duplicate deposit and transfer; approve() is omitted because it cannot affect balances or supply.
    /// @dev With H = 3, S = 1, and D = 3, the scheduler covers at most 27 complete schedules and 39 non-empty
    /// prefixes before executor-level path splitting. Symbolic actors and alias relations add further paths. The
    /// measured PASS explored 234 paths and 594 queries in 193,703 ms.
    ///
    /// forge-config: default.symbolic.invariant_depth = 3
    /// forge-config: default.symbolic.timeout = 600
    /// forge-config: default.symbolic.max_paths = 4096
    /// forge-config: default.symbolic.max_solver_queries = 10000
    /// forge-config: default.symbolic.storage_layout = "zero_init"
    function invariant_balanceAccounting() public view {
        assertEq(ghostSumOfAllBalances, weth.totalSupply(), "ghost balance sum != totalSupply");
    }

    function onBalanceStore(address, bytes32, bytes32, bytes32[] calldata, bytes32 oldValue, bytes32 newValue)
        external
    {
        require(msg.sender == address(HOOK_VM), "only storage hook");

        ghostSumOfAllBalances = ghostSumOfAllBalances - uint256(oldValue) + uint256(newValue);
    }
}
