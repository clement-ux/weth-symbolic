// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.31;

import {Base, ForceEther, RejectEther} from "../Base.t.sol";

contract WETHSymbolic_Rules is Base {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                               ✦✦✦ RULES VS INVARIANTS ✦✦✦                                ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  RULE                                                                                    ║
    // ║  ├─ Checks one chosen transition or fixed sequence: pre-state -> action -> post-state.   ║
    // ║  ├─ Preconditions must be reachable; assume only filters states that already exist.      ║
    // ║  └─ Symbolic inputs make that scenario cover a whole family of values.                   ║
    // ║                                                                                          ║
    // ║  INVARIANT                                                                               ║
    // ║  ├─ Checks a structural property after bounded, engine-generated call sequences.         ║
    // ║  └─ Use it for properties that must hold in every reachable state.                       ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                ✦✦✦ RULE CHECKLIST ✦✦✦                                    ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  WRAPPING RULES                                                                          ║
    // ║  ├─ [x] check_deposit: balance, supply, and reserve increase by amount                   ║
    // ║  ├─ [x] check_receive: same accounting effect as deposit                                 ║
    // ║  ├─ [x] check_withdraw: burns WETH and returns ETH one-for-one                           ║
    // ║  ├─ [x] check_deposit_withdraw_roundtrip: restores the initial ETH balance               ║
    // ║  └─ [x] check_forcedEthBreaksEquality: equality breaks; solvency remains                 ║
    // ║                                                                                          ║
    // ║  ERC20 RULES                                                                             ║
    // ║  ├─ [x] check_transfer: moves balances; supply, reserve, and third party unchanged       ║
    // ║  ├─ [x] check_transfer_itself: sender and unrelated balances unchanged                   ║
    // ║  ├─ [x] check_approval: sets the requested allowance                                     ║
    // ║  ├─ [x] check_transferFrom_finiteAllowance: decreases allowance by amount                ║
    // ║  └─ [x] check_transferFrom_maxAllowance: preserves maximum allowance                     ║
    // ║                                                                                          ║
    // ║  REVERT / ATOMICITY RULES                                                                ║
    // ║  ├─ [x] check_withdrawAboveBalance_revertsAtomically                                     ║
    // ║  ├─ [x] check_transferAboveBalance_revertsAtomically                                     ║
    // ║  ├─ [x] check_transferFromAboveBalanceOrAllowance_revertsAtomically                      ║
    // ║  └─ [x] check_failedEthDelivery_rollsBackWithdrawal                                      ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    uint256 internal constant INITIAL_WRAPPED_ETH = 10 ether;
    uint256 internal constant FORCED_ETH = 1 ether;

    ForceEther internal forceEther;
    RejectEther internal rejectEther;

    function setUp() public override {
        super.setUp();

        forceEther = new ForceEther();
        rejectEther = new RejectEther();
    }

    function check_deposit(uint96 amount, address user) public {
        vm.assume(user != address(0));
        vm.assume(user != address(weth));

        uint256 preBalance = weth.balanceOf(user);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;

        vm.deal(user, amount);
        vm.prank(user);
        weth.deposit{value: amount}();

        assertEq(weth.balanceOf(user), preBalance + amount);
        assertEq(weth.totalSupply(), preTotalSupply + amount);
        assertEq(address(weth).balance, preEthBalance + amount);
    }

    function check_receive(uint96 amount, address user) public {
        vm.assume(user != address(0));
        vm.assume(user != address(weth));

        uint256 preBalance = weth.balanceOf(user);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;

        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(weth).call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");

        assertEq(weth.balanceOf(user), preBalance + amount);
        assertEq(weth.totalSupply(), preTotalSupply + amount);
        assertEq(address(weth).balance, preEthBalance + amount);
    }

    function check_withdraw(uint96 amountDeposit, uint96 amountWithdraw, address user) public {
        vm.assume(user != address(0));
        vm.assume(user != address(weth));
        vm.assume(amountWithdraw <= amountDeposit);

        vm.deal(user, amountDeposit);
        uint256 preBalance = weth.balanceOf(user);
        uint256 wETHPreEthBalance = address(weth).balance;
        // No snapshot needed: totalSupply has a fixed slot known to be zero after setUp(), unlike balanceOf(user).
        //uint256 preTotalSupply = weth.totalSupply();

        vm.prank(user);
        weth.deposit{value: amountDeposit}();

        uint256 userPreEthBalance = user.balance;
        vm.prank(user);
        weth.withdraw(amountWithdraw);

        assertEq(weth.balanceOf(user), preBalance + amountDeposit - amountWithdraw);
        assertEq(weth.totalSupply(), amountDeposit - amountWithdraw);
        assertEq(address(weth).balance, wETHPreEthBalance + amountDeposit - amountWithdraw);
        assertEq(user.balance, userPreEthBalance + amountWithdraw);
    }

    /// @dev Constructs a reachable balance, then requests strictly more than that balance. The low-level call
    /// captures the expected revert so the rule can verify that every accounting term remains unchanged.
    function check_withdrawAboveBalance_revertsAtomically(uint96 amountDeposit, uint96 excess, address user) public {
        vm.assume(user != address(0));
        vm.assume(user != address(weth));
        vm.assume(excess > 0);

        vm.deal(user, amountDeposit);
        vm.prank(user);
        weth.deposit{value: amountDeposit}();

        uint256 preUserWethBalance = weth.balanceOf(user);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preReserve = address(weth).balance;
        uint256 preUserEthBalance = user.balance;
        uint256 amountWithdraw = preUserWethBalance + uint256(excess);

        vm.prank(user);
        (bool success,) = address(weth).call(abi.encodeWithSelector(weth.withdraw.selector, amountWithdraw));

        assertFalse(success, "withdraw above balance did not revert");
        assertEq(weth.balanceOf(user), preUserWethBalance, "failed withdraw changed user WETH balance");
        assertEq(weth.totalSupply(), preTotalSupply, "failed withdraw changed totalSupply");
        assertEq(address(weth).balance, preReserve, "failed withdraw changed WETH reserve");
        assertEq(user.balance, preUserEthBalance, "failed withdraw changed user ETH balance");
    }

    /// @dev The receiver has enough WETH to burn, but rejects the ETH sent by withdraw(). The resulting revert must
    /// roll back the preceding balance and totalSupply writes as well as the attempted ETH transfer.
    function check_failedEthDelivery_rollsBackWithdrawal(uint96 amount) public {
        vm.assume(amount > 0);

        address receiver = address(rejectEther);
        vm.deal(receiver, amount);
        vm.prank(receiver);
        weth.deposit{value: amount}();

        uint256 preReceiverWethBalance = weth.balanceOf(receiver);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preReserve = address(weth).balance;
        uint256 preReceiverEthBalance = receiver.balance;

        vm.prank(receiver);
        (bool success,) = address(weth).call(abi.encodeWithSelector(weth.withdraw.selector, amount));

        assertFalse(success, "withdraw unexpectedly delivered ETH");
        assertEq(weth.balanceOf(receiver), preReceiverWethBalance, "failed delivery changed receiver WETH balance");
        assertEq(weth.totalSupply(), preTotalSupply, "failed delivery changed totalSupply");
        assertEq(address(weth).balance, preReserve, "failed delivery changed WETH reserve");
        assertEq(receiver.balance, preReceiverEthBalance, "failed delivery changed receiver ETH balance");
    }

    function check_deposit_withdraw_roundtrip(uint96 amount) public {
        vm.deal(alice, amount);
        uint256 preEthBalance = alice.balance;

        vm.prank(alice);
        weth.deposit{value: amount}();

        vm.prank(alice);
        weth.withdraw(amount);

        assertEq(alice.balance, preEthBalance);
    }

    /// @dev Starts from the reachable equality reserve == totalSupply, then uses SELFDESTRUCT to transfer ETH
    /// without calling WETH's receive function. Supply therefore remains unchanged while the reserve increases.
    /// The scenario relies only on the forced ETH transfer, which remains part of SELFDESTRUCT after EIP-6780;
    /// it does not rely on the helper's code or storage being deleted.
    function check_forcedEthBreaksEquality() public {
        vm.deal(alice, INITIAL_WRAPPED_ETH);
        vm.prank(alice);
        weth.deposit{value: INITIAL_WRAPPED_ETH}();
        vm.deal(address(forceEther), FORCED_ETH);

        uint256 reserveBefore = address(weth).balance;
        uint256 supplyBefore = weth.totalSupply();
        assertEq(reserveBefore, supplyBefore, "initial reserve != totalSupply");

        forceEther.forceSend(payable(address(weth)));

        uint256 reserveAfter = address(weth).balance;
        uint256 supplyAfter = weth.totalSupply();

        assertEq(reserveAfter, reserveBefore + FORCED_ETH, "forced ETH not added to reserve");
        assertEq(supplyAfter, supplyBefore, "forced ETH changed totalSupply");
        assertGt(reserveAfter, supplyAfter, "forced ETH did not break equality");
        assertGe(reserveAfter, supplyAfter, "forced ETH made WETH insolvent");
    }

    /// @dev Deposits only construct reachable pre-states. Combinations whose total overflows uint256 revert
    /// during setup and are outside this rule's domain; amount <= senderInitialBalance remains explicit because
    /// it is the functional precondition of a successful transfer.
    function check_transfer(
        uint256 senderInitialBalance,
        uint256 receiverInitialBalance,
        uint256 thirdPartyInitialBalance,
        uint256 amount
    ) public {
        vm.assume(amount <= senderInitialBalance);

        vm.deal(alice, senderInitialBalance);
        vm.prank(alice);
        weth.deposit{value: senderInitialBalance}();

        vm.deal(bobby, receiverInitialBalance);
        vm.prank(bobby);
        weth.deposit{value: receiverInitialBalance}();

        vm.deal(carol, thirdPartyInitialBalance);
        vm.prank(carol);
        weth.deposit{value: thirdPartyInitialBalance}();

        uint256 preFromBalance = weth.balanceOf(alice);
        uint256 preToBalance = weth.balanceOf(bobby);
        uint256 preThirdPartyBalance = weth.balanceOf(carol);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;

        vm.prank(alice);
        bool success = weth.transfer(bobby, amount);

        assertTrue(success);
        assertEq(weth.balanceOf(alice), preFromBalance - amount);
        assertEq(weth.balanceOf(bobby), preToBalance + amount);
        assertEq(weth.balanceOf(carol), preThirdPartyBalance);
        assertEq(weth.totalSupply(), preTotalSupply);
        assertEq(address(weth).balance, preEthBalance);
    }

    function check_transfer_itself(uint256 senderInitialBalance, uint256 thirdPartyInitialBalance, uint256 amount)
        public
    {
        vm.assume(amount <= senderInitialBalance);

        vm.deal(alice, senderInitialBalance);
        vm.prank(alice);
        weth.deposit{value: senderInitialBalance}();

        vm.deal(carol, thirdPartyInitialBalance);
        vm.prank(carol);
        weth.deposit{value: thirdPartyInitialBalance}();

        uint256 preFromBalance = weth.balanceOf(alice);
        uint256 preThirdPartyBalance = weth.balanceOf(carol);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;

        vm.prank(alice);
        bool success = weth.transfer(alice, amount);

        assertTrue(success);
        assertEq(weth.balanceOf(alice), preFromBalance);
        assertEq(weth.balanceOf(carol), preThirdPartyBalance);
        assertEq(weth.totalSupply(), preTotalSupply);
        assertEq(address(weth).balance, preEthBalance);
    }

    /// @dev Alice and Bobby are fixed to keep mapping keys concrete and counterexamples replayable. The deposited
    /// balance and excess remain symbolic. Self-transfer behavior is covered separately by check_transfer_itself.
    function check_transferAboveBalance_revertsAtomically(uint96 initialBalance, uint96 excess) public {
        vm.assume(excess > 0);

        vm.deal(alice, initialBalance);
        vm.prank(alice);
        weth.deposit{value: initialBalance}();

        uint256 preFromBalance = weth.balanceOf(alice);
        uint256 preToBalance = weth.balanceOf(bobby);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preReserve = address(weth).balance;
        uint256 amount = uint256(initialBalance) + uint256(excess);

        vm.prank(alice);
        (bool success,) = address(weth).call(abi.encodeWithSelector(weth.transfer.selector, bobby, amount));

        assertFalse(success, "transfer above balance did not revert");
        assertEq(weth.balanceOf(alice), preFromBalance, "failed transfer changed sender balance");
        assertEq(weth.balanceOf(bobby), preToBalance, "failed transfer changed recipient balance");
        assertEq(weth.totalSupply(), preTotalSupply, "failed transfer changed totalSupply");
        assertEq(address(weth).balance, preReserve, "failed transfer changed WETH reserve");
    }

    function check_approval(address from, address to, uint256 amount) public {
        vm.prank(from);
        bool success = weth.approve(to, amount);

        assertTrue(success);
        assertEq(weth.allowance(from, to), amount);
    }

    function check_transferFrom_finiteAllowance(address from, address to, uint256 initialAllowance, uint256 amount)
        public
    {
        vm.assume(amount <= initialAllowance);
        vm.assume(initialAllowance != type(uint256).max);
        vm.assume(from != to);

        vm.deal(from, amount);
        vm.prank(from);
        weth.deposit{value: amount}();

        vm.prank(from);
        weth.approve(to, initialAllowance);

        uint256 preFromBalance = weth.balanceOf(from);
        uint256 preToBalance = weth.balanceOf(to);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;
        uint256 preAllowance = weth.allowance(from, to);

        vm.prank(to);
        weth.transferFrom(from, to, amount);

        assertEq(weth.balanceOf(from), preFromBalance - amount);
        assertEq(weth.balanceOf(to), preToBalance + amount);
        assertEq(weth.totalSupply(), preTotalSupply);
        assertEq(address(weth).balance, preEthBalance);
        assertEq(weth.allowance(from, to), preAllowance - amount);
    }

    function check_transferFrom_maxAllowance(address from, address to, uint256 amount) public {
        vm.assume(from != to);

        vm.deal(from, amount);
        vm.prank(from);
        weth.deposit{value: amount}();

        vm.prank(from);
        weth.approve(to, type(uint256).max);

        uint256 preFromBalance = weth.balanceOf(from);
        uint256 preToBalance = weth.balanceOf(to);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preEthBalance = address(weth).balance;
        uint256 preAllowance = weth.allowance(from, to);
        assertEq(preAllowance, type(uint256).max);

        vm.prank(to);
        weth.transferFrom(from, to, amount);

        assertEq(weth.balanceOf(from), preFromBalance - amount);
        assertEq(weth.balanceOf(to), preToBalance + amount);
        assertEq(weth.totalSupply(), preTotalSupply);
        assertEq(address(weth).balance, preEthBalance);
        assertEq(weth.allowance(from, to), preAllowance);
    }

    /// @dev Alice, Bobby, and Carol are fixed owner, spender, and recipient roles so mapping keys remain concrete
    /// and counterexamples replayable. Symbolic values cover insufficient allowance, insufficient balance, and both.
    /// In the balance-only case, the allowance is reduced before the later failure, so its rollback is explicit.
    function check_transferFromAboveBalanceOrAllowance_revertsAtomically(
        uint96 initialBalance,
        uint96 initialAllowance,
        uint96 amount
    ) public {
        vm.assume(amount > initialBalance || amount > initialAllowance);

        vm.deal(alice, initialBalance);
        vm.prank(alice);
        weth.deposit{value: initialBalance}();

        vm.prank(alice);
        weth.approve(bobby, initialAllowance);

        uint256 preOwnerBalance = weth.balanceOf(alice);
        uint256 preRecipientBalance = weth.balanceOf(carol);
        uint256 preAllowance = weth.allowance(alice, bobby);
        uint256 preTotalSupply = weth.totalSupply();
        uint256 preReserve = address(weth).balance;

        vm.prank(bobby);
        (bool success,) = address(weth).call(abi.encodeWithSelector(weth.transferFrom.selector, alice, carol, amount));

        assertFalse(success, "invalid transferFrom did not revert");
        assertEq(weth.balanceOf(alice), preOwnerBalance, "failed transferFrom changed owner balance");
        assertEq(weth.balanceOf(carol), preRecipientBalance, "failed transferFrom changed recipient balance");
        assertEq(weth.allowance(alice, bobby), preAllowance, "failed transferFrom changed allowance");
        assertEq(weth.totalSupply(), preTotalSupply, "failed transferFrom changed totalSupply");
        assertEq(address(weth).balance, preReserve, "failed transferFrom changed WETH reserve");
    }
}
