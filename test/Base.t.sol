// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// --- Forge
import {Test} from "forge-std/Test.sol";

// --- WETH
import {WETH} from "../src/WETH.sol";

contract Symbolic_WETH_Shared_Test is Test {
    WETH internal weth;

    function setUp() public virtual {
        weth = new WETH();
        vm.setArbitraryStorage(address(weth), true);
    }

    function check_deposit(uint256 amount, address account) public {
        // --- Preconditions
        vm.assume(account != address(weth));
        uint256 balanceBefore = weth.balanceOf(account);
        uint256 supplyBefore = weth.totalSupply();
        vm.assume(balanceBefore <= supplyBefore);

        deal(address(weth), supplyBefore); // Make arbitrary storage real.

        // --- Action
        deal(account, amount);
        vm.prank(account);
        weth.deposit{value: amount}();

        // --- Postconditions
        // WETH Balances
        uint256 balanceAfter = weth.balanceOf(account);
        // Keep: without it, a decrease would underflow the subtraction below and revert,
        // and a reverting path ends silently instead of failing the test.
        assertGe(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, amount);

        // ETH Balances
        uint256 ethBalanceAfter = address(weth).balance;
        assertGe(ethBalanceAfter, supplyBefore); // Same reasoning as above.
        assertEq(ethBalanceAfter - supplyBefore, amount);

        // Supply
        assertEq(ethBalanceAfter, weth.totalSupply());
    }

    /*
        function check_withdraw(uint256 amount, address account) public {
            // --- Preconditions
            uint256 balanceBefore = weth.balanceOf(account);
            uint256 supplyBefore = weth.totalSupply();

            // --- Action
            deal(address(weth), amount);
            vm.prank(account);
            weth.withdraw(amount);

            // --- Postconditions
            assertEq(weth.balanceOf(account), balanceBefore - amount);
            assertEq(weth.totalSupply(), supplyBefore - amount);
        }
    */
}
