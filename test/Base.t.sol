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
        uint256 balanceBefore = weth.balanceOf(account);
        //uint256 supplyBefore = weth.totalSupply();
        //vm.assume(balanceBefore <= supplyBefore);

        // --- Action
        deal(account, amount);
        vm.prank(account);
        weth.deposit{value: amount}();

        // --- Postconditions
        uint256 balanceAfter = weth.balanceOf(account);
        assertGe(balanceAfter, balanceBefore);
        //assertEq(balanceAfter - balanceBefore, amount);

        //uint256 supplyAfter = weth.totalSupply();
        //assertGe(supplyAfter, supplyBefore);
        //assertEq(supplyAfter - supplyBefore, amount);
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
