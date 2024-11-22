// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the unstake function
 */
contract CoordinatorUnstakeTest is CoordinatorBaseTest {
    function test_UnstakeActiveExecutor(uint192 time) public {
        vm.assume(time > minimumRegistrationPeriod);
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        coordinator.setLastRegistrationTimestamp(time - minimumRegistrationPeriod, executor);

        vm.warp(time);
        vm.prank(executor);
        coordinator.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));

        (
            uint256 balance,
            bool active,
            bool initialized,
            uint32 arrayIndex,
            uint8 roundsCheckedInEpoch,
            uint8 lastCheckinRound,
            uint96 lastCheckinEpoch,
            uint96 executionsInEpochCreatedBeforeEpoch,
            uint256 lastRegistrationTimestamp,
            uint256 registeredModules
        ) = coordinator.executorInfo(executor);
        assertFalse(active, "active");
        assertFalse(initialized, "initialized");
        assertEq(balance, 0, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(coordinator.activeExecutors(0), address(0), "in activeExecutors array");
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 0, "number of active executors mismatch");
        assertEq(lastRegistrationTimestamp, 0, "registration timestamp mismatch");
        assertEq(executionsInEpochCreatedBeforeEpoch, 0, "executions in epoch mismatch");
        assertEq(roundsCheckedInEpoch, 0, "rounds checked in epoch mismatch");
        assertEq(registeredModules, 0, "registered modules mismatch");
    }

    function test_UnstakeBeforeMinimumRegistrationPeriod(uint192 time) public {
        vm.assume(time > 1);
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );

        vm.warp(time - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.MinimumRegistrationPeriodNotOver.selector);
        coordinator.unstake();
    }

    function test_UnstakeInactiveExecutor() public {
        // should not modify activeExecutors array when unstaking an inactive executor
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);

        coordinator.stake(modulesToRegister);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingAmountPerModule * 2,
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

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        coordinator.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(coordinator.activeExecutors(0), executor, "in active executors array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeInvalidBlockTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - 1
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.unstake();
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.unstake();
    }
}