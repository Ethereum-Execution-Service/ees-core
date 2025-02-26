// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";
import {IModuleRegistry} from "../../src/interfaces/IModuleRegistry.sol";

/**
 * @notice Tests for the stake function
 */
contract CoordinatorStakeTest is CoordinatorBaseTest {
    function test_Stake(uint256 time) public {
        // should be able to stake if block.timestamp is in selection phase or after epoch
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime
        );

        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);
        vm.warp(time);
        coordinator.stake(modulesToRegister);
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
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
        assertEq(balance, stakingAmountPerModule * 2, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(coordinator.activeExecutors(0), executor, "not in activeExecutors array");
        assertEq(startBalanceExecutor - endBalanceExecutor, stakingAmountPerModule * 2, "executor balance mismatch");
        assertEq(endBalanceProtocol - startBalanceProtocol, stakingAmountPerModule * 2, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
        assertEq(lastRegistrationTimestamp, time, "registration timestamp mismatch");
        assertEq(executionsInEpochCreatedBeforeEpoch, 0, "executions in epoch mismatch");
        assertEq(roundsCheckedInEpoch, 0, "rounds checked in epoch mismatch");
        assertEq(registeredModules, modulesToRegister, "registered modules mismatch");
    }

    function test_StakeInvalidTime(uint256 time) public {
        // should revert if block.timestamp is between selection phase and end of epoch.
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );
        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.stake(modulesToRegister);
    }

    function test_StakeArrayNotFull0() public {
        // should put executor in at right index upons staking in a non-full array
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        coordinator.unstake();
        vm.prank(thirdExecutor);
        coordinator.stake(modulesToRegister);

        assertEq(coordinator.activeExecutors(0), secondExecutor, "0th index mismatch");
        assertEq(coordinator.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(coordinator.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakeArrayNotFull1() public {
        // should put executor in at right index upons staking in a non-full array
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(secondExecutor);
        coordinator.unstake();

        vm.prank(thirdExecutor);
        coordinator.stake(modulesToRegister);

        assertEq(coordinator.activeExecutors(0), executor, "0th index mismatch");
        assertEq(coordinator.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(coordinator.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakingWhenAlreadyStaked() public {
        // should revert if executor is already staked
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.AlreadyStaked.selector);
        coordinator.stake(modulesToRegister);
    }

    function test_NumberOfRegisteredModulesBelowMinimum(uint8 numberOfModules) public {
        // should revert if less than 2 modules are registered
        vm.assume(numberOfModules < 2);
        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.NumberOfRegisteredModulesBelowMinimum.selector);
        coordinator.stake(numberOfModules);
    }

    function test_UsingUnsupportedModules() public {
        // should only register for modules which are supported in coordiantor. Module 2 is not supported.
        uint256 modulesToRegister = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3);
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256 endBalanceExecutor = token0.balanceOf(executor);

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

        assertEq(balance, stakingAmountPerModule * 3, "balance mismatch");
        assertEq(startBalanceExecutor - endBalanceExecutor, stakingAmountPerModule * 3, "executor balance mismatch");
        assertEq(registeredModules, (1 << 0) | (1 << 1) | (1 << 2), "registered modules mismatch");
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
    }
}
