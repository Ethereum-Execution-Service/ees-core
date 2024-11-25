// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the slashInactiveExecutor function
 */
contract CoordinatorSlashInactiveTest is CoordinatorBaseTest {
    function test_InactiveSlashing(address slasher, uint256 time, bytes32 seed) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake(modulesToRegister);

        (uint256 startBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(1);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
        (uint256 endBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);
        (uint256 balance, bool active, bool initialized, uint32 arrayIndex,,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmountPerModule * 2 - inactiveSlashingAmountPerModule * 2, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + (inactiveSlashingAmountPerModule * 2) / 2, "slasher balance mismatch");
    }

    function test_InactiveSlashingNotExecutor(address slasher, uint256 time, bytes32 seed) public {
        // an un-staked (not registered executor) caller and recipient should be able to slash and receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);


        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(1);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);

        (uint256 balance, bool active, bool initialized, uint32 arrayIndex,,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmountPerModule * 2 - inactiveSlashingAmountPerModule * 2, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + (inactiveSlashingAmountPerModule * 2) / 2, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher, uint40 epoch, bytes32 seed) public {
        // should revert with RoundExecuted if round was executed
        vm.assume(slasher != executor);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake(modulesToRegister);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(epoch);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingBalanceThresholdPerModule * 2 + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                roundsCheckedInEpoch: 0,
                lastCheckinEpoch: epoch,
                lastCheckinRound: 0,
                executionsInRoundsInEpoch: 0,
                lastRegistrationTimestamp: 0,
                registeredModules: modulesToRegister
            }),
            executor
        );

        vm.prank(slasher);
        vm.expectRevert(ICoordinator.RoundExecuted.selector);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
    }

    function test_SlashingEndBalanceBelowThreshold(address slasher, bytes32 seed) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake(modulesToRegister);

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(1);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingBalanceThresholdPerModule * 2 + 1,
                active: true,
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
        (uint256 startBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);
        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.prank(slasher);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
        (uint256 endBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);
        (uint256 balance, bool active, bool initialized, uint32 arrayIndex,,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingBalanceThresholdPerModule * 2 + 1 - inactiveSlashingAmountPerModule * 2, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + (inactiveSlashingAmountPerModule * 2) / 2, "slasher balance mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_SlashingBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - coordinator.getSlashingDuration() - 1);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashInactiveExecutor(executor, 0, secondExecutor);
    }

    function test_SlashingAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashInactiveExecutor(executor, 0, secondExecutor);
    }

    function test_SlashingNotSelectedExecutor(bytes32 seed, uint8 round, uint32 numOfactiveExecutors) public {
        // should revert with ExecutorNotSelectedForRound if executor was not selected for round
        vm.assume(numOfactiveExecutors > 0);
        round = uint8(bound(round, 0, roundsPerEpoch - 1));
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setSeed(seed);
        coordinator.setNumberOfActiveExecutors(numOfactiveExecutors);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, round))) % uint256(numOfactiveExecutors) != 0);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(ICoordinator.ExecutorNotSelectedForRound.selector);
        coordinator.slashInactiveExecutor(executor, round, secondExecutor);
    }

    function test_SlashingRoundExceedingTotal(uint8 round) public {
        // should revert with RoundExceedingTotal if round is greater than total rounds per epoch
        round = uint8(bound(round, roundsPerEpoch, type(uint8).max));

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.RoundExceedingTotal.selector);
        coordinator.slashInactiveExecutor(executor, round, secondExecutor);
    }
}