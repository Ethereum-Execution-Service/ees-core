// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the initiateEpoch function
 */
contract CoordinatorInitiateEpochTest is CoordinatorBaseTest {
    function test_InitiateEpoch(address caller, uint256 time) public {
        // should be callable by anyone
        time = bound(time, defaultEpochEndTime, type(uint192).max);
        // should increase epochEndTime and increment epoch. Callable by anyone. Should set executedRounds to all false
        coordinator.setEpoch(0);
        vm.warp(time);
        vm.prank(caller);
        coordinator.initiateEpoch();
        assertEq(coordinator.epochEndTime(), time + coordinator.getEpochDuration(), "epoch mismatch");
        assertEq(coordinator.epoch(), 1, "epoch mismatch");
    }

    function test_InitiateBeforeTime(address caller, uint256 time) public {
        // should revert with EpochNotEnded if epochEndTime is not reached
        time = bound(time, 0, defaultEpochEndTime - 1);
        vm.warp(time);
        vm.prank(caller);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.initiateEpoch();
    }

    function test_InitiateEpochReceivingExecutorsInfoUpdate() public {
        // should update executor info of receiving executors accordingly
        vm.warp(defaultEpochEndTime);

        // 3 executors are staked with 2 modules each
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);
        vm.prank(thirdExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setExecutionsInRoundsInEpoch(8, executor);
        coordinator.setExecutionsInRoundsInEpoch(2, secondExecutor);
        coordinator.setExecutionsInRoundsInEpoch(1, thirdExecutor);

        // first executor checked in 2 rounds
        coordinator.setRoundsCheckedInEpoch(2, executor);
        coordinator.setRoundsCheckedInEpoch(1, secondExecutor);
        coordinator.setRoundsCheckedInEpoch(1, thirdExecutor);

        address[] memory poolCutReceivers = new address[](3);
        poolCutReceivers[0] = executor;
        poolCutReceivers[1] = secondExecutor;
        poolCutReceivers[2] = thirdExecutor;
        coordinator.setPoolCutReceivers(poolCutReceivers);

        // 10 jobs are executed in the epoch
        coordinator.setExecutedJobsInRoundsOfEpoch(10);
        // epoch pool balance is 1000000
        coordinator.setEpochPoolBalance(1000000);

        coordinator.initiateEpoch();

        // protocol balance should be 100000 (10% of 1000000)
        assertEq(coordinator.protocolBalance(), 100000, "protocol balance mismatch");

        // max reward per execution is 54000
        // share cap is 900000 / 5 = 180000

        // executor should get max reward capped by share (2 * 180000 = 360000)
        // execution basis: 54000 * 8 = 432000
        (uint256 executorBalance,,,, uint8 roundsCheckedInEpochExecutor,,, uint96 executionsInRoundsInEpochExecutor,,) =
            coordinator.executorInfo(executor);
        assertEq(executorBalance, stakingAmountPerModule * 2 + 360000, "executor balance mismatch");
        assertEq(roundsCheckedInEpochExecutor, 0, "rounds checked in epoch mismatch executor");
        assertEq(executionsInRoundsInEpochExecutor, 0, "executions in rounds in epoch mismatch executor");

        // execution basis: 54000 * 2 = 108000
        (
            uint256 secondExecutorBalance,
            ,
            ,
            ,
            uint8 roundsCheckedInEpochSecondExecutor,
            ,
            ,
            uint96 executionsInRoundsInEpochSecondExecutor,
            ,
        ) = coordinator.executorInfo(secondExecutor);
        assertEq(secondExecutorBalance, stakingAmountPerModule * 2 + 108000, "second executor balance mismatch");
        assertEq(roundsCheckedInEpochSecondExecutor, 0, "rounds checked in epoch mismatch second executor");
        assertEq(executionsInRoundsInEpochSecondExecutor, 0, "executions in rounds in epoch mismatch second executor");
        // execution basis: 54000 * 1 = 54000
        (
            uint256 thirdExecutorBalance,
            ,
            ,
            ,
            uint8 roundsCheckedInEpochThirdExecutor,
            ,
            ,
            uint96 executionsInRoundsInEpochThirdExecutor,
            ,
        ) = coordinator.executorInfo(thirdExecutor);
        assertEq(thirdExecutorBalance, stakingAmountPerModule * 2 + 54000, "third executor balance mismatch");
        assertEq(roundsCheckedInEpochThirdExecutor, 0, "rounds checked in epoch mismatch third executor");
        assertEq(executionsInRoundsInEpochThirdExecutor, 0, "executions in rounds in epoch mismatch third executor");

        // pool balance of new epoch should be updated properly
        assertEq(coordinator.epochPoolBalance(), 1000000 - 100000 - 360000 - 108000 - 54000, "pool balance mismatch");
    }

    function test_InitiateEpochBalancesWithNoExecutedJobs() public {
        // should just take protocol cut if no jobs are executed
        vm.warp(defaultEpochEndTime);

        coordinator.setEpochPoolBalance(1000000);
        coordinator.initiateEpoch();

        assertEq(coordinator.protocolBalance(), 100000, "protocol balance mismatch");
        assertEq(coordinator.epochPoolBalance(), 1000000 - 100000, "pool balance mismatch");
    }

    function test_InitiateEpochEmptyingPool() public {
        // should empty pool correctly upon maximal participation
        vm.warp(defaultEpochEndTime);

        // 3 executors are staked with 2 modules each
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);
        vm.prank(thirdExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setExecutionsInRoundsInEpoch(20, executor);
        coordinator.setExecutionsInRoundsInEpoch(20, secondExecutor);
        coordinator.setExecutionsInRoundsInEpoch(10, thirdExecutor);

        // 5 rounds in total
        // first two executors checked in 2 rounds
        coordinator.setRoundsCheckedInEpoch(2, executor);
        coordinator.setRoundsCheckedInEpoch(2, secondExecutor);
        coordinator.setRoundsCheckedInEpoch(1, thirdExecutor);

        address[] memory poolCutReceivers = new address[](3);
        poolCutReceivers[0] = executor;
        poolCutReceivers[1] = secondExecutor;
        poolCutReceivers[2] = thirdExecutor;
        coordinator.setPoolCutReceivers(poolCutReceivers);

        // 10 jobs are executed in the epoch
        coordinator.setExecutedJobsInRoundsOfEpoch(10);
        // epoch pool balance is 1000000
        coordinator.setEpochPoolBalance(1000000);

        coordinator.initiateEpoch();

        // protocol balance should be 100000 (10% of 1000000)
        assertEq(coordinator.protocolBalance(), 100000, "protocol balance mismatch");

        // max reward per execution is 54000
        // share cap is 900000 / 5 = 180000

        // executors should get max reward capped by share (2 * 180000 = 360000 and 1 * 180000 = 180000)
        // execution basis: 54000 * 20 = 1080000
        (uint256 executorBalance,,,,,,,,,) = coordinator.executorInfo(executor);
        assertEq(executorBalance, stakingAmountPerModule * 2 + 360000, "executor balance mismatch");

        // execution basis: 54000 * 20 = 1080000
        (uint256 secondExecutorBalance,,,,,,,,,) = coordinator.executorInfo(secondExecutor);
        assertEq(secondExecutorBalance, stakingAmountPerModule * 2 + 360000, "second executor balance mismatch");

        // execution basis: 54000 * 10 = 540000
        (uint256 thirdExecutorBalance,,,,,,,,,) = coordinator.executorInfo(thirdExecutor);
        assertEq(thirdExecutorBalance, stakingAmountPerModule * 2 + 180000, "third executor balance mismatch");

        // pool balance of new epoch should be updated properly
        assertEq(coordinator.epochPoolBalance(), 0, "pool balance mismatch");
    }
}
