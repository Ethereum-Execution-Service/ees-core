// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the topup function
 */
contract CoordinatorTopupTest is CoordinatorBaseTest {
    function test_TopupToAboveThreshold(uint256 time, uint256 topUpAmount, uint256 startingBalance) public {
        // should activate executor when balance after topup is above coordinator amount
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );
        startingBalance = bound(startingBalance, 0, stakingBalanceThresholdPerModule * 2 - 1);
        topUpAmount = bound(topUpAmount, stakingAmountPerModule * 2 - startingBalance, token0.balanceOf(executor));
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                roundsCheckedInEpoch: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                executionsInRoundsInEpoch: 0,
                lastRegistrationTimestamp: 0,
                registeredModules: modulesToRegister
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.warp(time);
        vm.prank(executor);
        coordinator.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));

        (uint256 balance, bool active, bool initialized, uint32 arrayIndex,,,,,,) = coordinator.executorInfo(executor);
        assertTrue(active, "not active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_TopupToBelowThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should not activate executor when balance after topup is below coordinator amount
        startingBalance = bound(startingBalance, 0, stakingBalanceThresholdPerModule * 2 - 1);
        topUpAmount = bound(topUpAmount, 0, stakingAmountPerModule * 2 - startingBalance - 1);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                roundsCheckedInEpoch: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                executionsInRoundsInEpoch: 0,
                lastRegistrationTimestamp: 0,
                registeredModules: modulesToRegister
            }),
            executor
        );
        vm.prank(executor);
        vm.expectRevert(ICoordinator.FinalBalanceBelowMinimum.selector);
        coordinator.topup(topUpAmount);
    }

    function test_TopupNotAnExecutor() public {
        // should revert if not a executor
        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotInitializedExecutor.selector);
        coordinator.topup(stakingAmountPerModule);
    }

    function test_TopupInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.topup(stakingAmountPerModule);
    }
}
