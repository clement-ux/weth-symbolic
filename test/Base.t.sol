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

        // --- Make arbitrary storage real.
        deal(address(weth), supplyBefore);

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
        uint256 ethBalanceContractAfter = address(weth).balance;
        assertGe(ethBalanceContractAfter, supplyBefore); // Same reasoning as above.
        assertEq(ethBalanceContractAfter - supplyBefore, amount);

        // Supply
        assertEq(ethBalanceContractAfter, weth.totalSupply());
    }

    function check_withdraw(uint256 amount, address account) public {
        // --- Preconditions
        vm.assume(account != address(weth));
        uint256 balanceBefore = weth.balanceOf(account);
        uint256 supplyBefore = weth.totalSupply();
        vm.assume(balanceBefore <= supplyBefore);

        // --- Make arbitrary storage real.
        deal(address(weth), supplyBefore);
        // Pin the account's ETH balance: the symbolic engine reads an arbitrary initial
        // balance for a symbolic address but credits the withdrawal to an empty account,
        // so `after - before == amount` yields spurious counterexamples.
        deal(account, 0);

        // --- Action
        vm.prank(account);
        weth.withdraw(amount);

        // --- Postconditions
        // WETH Balances
        uint256 balanceAfter = weth.balanceOf(account);
        assertGe(balanceBefore, amount);
        assertEq(balanceBefore - amount, balanceAfter);

        // ETH Balances: Account;
        assertEq(account.balance, amount);
        // ETH Balances: WETH
        uint256 ethBalanceContractAfter = address(weth).balance;
        assertGe(supplyBefore, amount);
        assertEq(supplyBefore - amount, ethBalanceContractAfter);

        // Supply
        assertEq(ethBalanceContractAfter, weth.totalSupply());
    }
}
