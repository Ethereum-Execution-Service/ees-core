// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";

import "./Base.t.sol";
/**
 * @notice Tests for the withdrawStakingBalance function
 */

contract CoordinatorWithdrawStakingBalanceTest is CoordinatorBaseTest {
    function test_BalanceAboveThresholdAfterWithdrawal(uint32 withdrawalAmount, uint32 addedBalance) public {
        // should succesfuly withdraw if balance after withdrawal is above threshold and reduce internal balance

        // make sure coordinator has ERC20 tokens
        setERC20TestTokens(address(coordinator));

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        addedBalance = uint32(bound(addedBalance, 0, token0.balanceOf(executor)));
        withdrawalAmount = uint32(bound(withdrawalAmount, 0, addedBalance));

        coordinator.setExecutorBalance(stakingAmountPerModule * 2 + addedBalance, executor);

        uint256 startBalance = token0.balanceOf(executor);
        vm.prank(executor);
        coordinator.withdrawStakingBalance(withdrawalAmount);

        (uint256 internalBalance,,,,,,,,,) = coordinator.executorInfo(executor);

        assertEq(
            internalBalance,
            stakingAmountPerModule * 2 + addedBalance - withdrawalAmount,
            "executor internal balance mismatch"
        );
        assertEq(token0.balanceOf(executor), startBalance + withdrawalAmount, "executor token balance mismatch");
    }

    function test_RevertWhen_BalanceBelowThresholdAfterWithdrawal(uint256 withdrawalAmount) public {
        // should revert if balance after withdrawal is below threshold
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        // Set withdrawal amount to be more than what would leave balance above threshold
        uint256 threshold = stakingAmountPerModule * 2; // 2 modules registered
        uint256 currentBalance = stakingAmountPerModule * 2; // initial staking balance
        withdrawalAmount = bound(withdrawalAmount, currentBalance - threshold + 1, currentBalance);

        vm.prank(executor);
        vm.expectRevert(ICoordinator.FinalBalanceBelowMinimum.selector);
        coordinator.withdrawStakingBalance(withdrawalAmount);
    }

    function test_WithdrawalNotInitializedExecutor(address caller, uint256 amount) public {
        // should revert if caller is not an initialized executor
        vm.assume(caller != executor);
        vm.assume(caller != secondExecutor);
        vm.assume(caller != thirdExecutor);
        vm.prank(caller);
        vm.expectRevert(ICoordinator.NotInitializedExecutor.selector);
        coordinator.withdrawStakingBalance(amount);
    }
}
