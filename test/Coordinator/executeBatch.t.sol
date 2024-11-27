// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the executeBatch function
 */
contract CoordinatorExecuteBatchTest is CoordinatorBaseTest {

  function test_ExecuteBatchInEpochOutsideRound(uint256 time) public {
    // executing batch outside rounds should increase next epoch pool balance and take execution tax from executor
      time = bound(
          time,
          defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
          defaultEpochEndTime - 1
      );

      uint256 timeIntoRounds =
          coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
      vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() >= roundDuration);

      vm.prank(executor);
      coordinator.stake(modulesToRegister);
      uint256[] memory indices = new uint256[](1);
      indices[0] = 0;
      uint256[] memory gasLimits = new uint256[](1);
      gasLimits[0] = 500_000;

      vm.warp(time);
      vm.prank(executor);
      (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
      (uint256 balance,,,,,,,,,) = coordinator.executorInfo(executor);
      assertEq(successfulExecutions, 1, "number of successful executions mismatch");
      assertEq(balance, stakingAmountPerModule * 2 - executionTax, "executor balance mismatch");
      assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }

    function test_InRoundModuleAlreadySupportedExecutor(bytes32 seed) public {
        // designated executor already supports modules, so execute batch by other executor should fail
        // first executor is selected for round 0
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setSeed(seed);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(secondExecutor);
        vm.expectRevert(abi.encodeWithSelector(ICoordinator.DesignatedExecutorSupportsModules.selector));
        coordinator.executeBatch(indices, gasLimits, secondExecutor, 0);
    }

    function test_InRoundModuleAlreadySupportedNonExecutor(bytes32 seed) public {
        // designated executor already supports modules, so execute batch by non-executor should fail
        // executor is selected for round 0
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        coordinator.setSeed(seed);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(nonStakedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ICoordinator.DesignatedExecutorSupportsModules.selector));
        coordinator.executeBatch(indices, gasLimits, secondExecutor, 0);
    }

    function test_InRoundCheckInDesignatedExecutor(uint256 epochPoolBalance) public {
        // first time designated executor is executing this round, should update lastCheckinRound and lastCheckinEpoch
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        coordinator.setEpoch(10);
        coordinator.setEpochPoolBalance(epochPoolBalance);

        uint256 prevPoolBalance = coordinator.getEpochPoolBalance();

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(executor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
        (uint256 balance,,,,, uint8 lastCheckinRound, uint96 lastCheckinEpoch,,,) = coordinator.executorInfo(executor);
        uint256 newPoolBalance = coordinator.getEpochPoolBalance();
        assertEq(newPoolBalance, prevPoolBalance, "pool balance mismatch");

        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(balance, stakingAmountPerModule * 2 - executionTax, "executor balance mismatch");
        assertEq(lastCheckinEpoch, 10, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
        assertEq(coordinator.protocolBalance(), executionTax, "protocol balance mismatch");
    }

    function test_AlreadyCheckedInDesignatedExecutor(uint256 time) public {
        // as designated executor should be able to execute if already checked in current round/epoch but should not update those
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        coordinator.setEpoch(10);
        coordinator.setEpochPoolBalance(100);

        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingAmountPerModule * 2,
                active: true,
                initialized: true,
                arrayIndex: 0,
                roundsCheckedInEpoch: 0,
                lastCheckinEpoch: 10,
                lastCheckinRound: 0,
                executionsInRoundsInEpoch: 0,
                lastRegistrationTimestamp: block.timestamp,
                registeredModules: modulesToRegister
            }),
            executor
        );

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(executor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);

        (uint256 balance,,,,, uint8 lastCheckinRound, uint96 lastCheckinEpoch,,,) = coordinator.executorInfo(executor);
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(lastCheckinEpoch, 10, "latest executed epoch mismatch");
        assertEq(balance, stakingAmountPerModule * 2 - executionTax, "executor balance mismatch");
        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
        assertEq(coordinator.protocolBalance(), executionTax, "protocol balance mismatch");
    }

    function test_JobExecutionReverts() public {
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        jobRegistry.setRevertOnExecute(true);

        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
        (uint256 balance,,,,,,,,,) = coordinator.executorInfo(executor);

        assertEq(successfulExecutions, 0, "number of successful executions mismatch");
        assertEq(balance, stakingAmountPerModule * 2, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_BeforeRoundsExecutor(uint256 time) public {
        // executor should be able to execute before rounds start
        time = bound(
            time, 0, defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
        (uint256 balance,,,,,,,,,) = coordinator.executorInfo(executor);

        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(balance, stakingAmountPerModule * 2 - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }

    function test_BeforeRoundsNonExecutor(uint256 time) public {
        // non-staked executor should be able to execute before rounds start
        time = bound(
            time, 0, defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() - 1
        );
        vm.prank(nonStakedExecutor);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        uint256 startBalance = token0.balanceOf(nonStakedExecutor);

        vm.warp(time);
        vm.prank(nonStakedExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, nonStakedExecutor, 0);

        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(token0.balanceOf(nonStakedExecutor), startBalance - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }

    function test_AfterRoundsExecutor(uint256 time) public {
        // executor should be able to execute after rounds start
        time = bound(time, defaultEpochEndTime, type(uint192).max);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
        (uint256 balance,,,,,,,,,) = coordinator.executorInfo(executor);

        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(balance, stakingAmountPerModule * 2 - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }

    function test_AfterRoundsNonExecutor(uint256 time) public {
        // non-staked executor should be able to execute after rounds start
        time = bound(time, defaultEpochEndTime, type(uint192).max);
        vm.prank(nonStakedExecutor);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        uint256 startBalance = token0.balanceOf(nonStakedExecutor);

        vm.warp(time);
        vm.prank(nonStakedExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, nonStakedExecutor, 0);

        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(token0.balanceOf(nonStakedExecutor), startBalance - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }


    function test_OutsideRoundsNonExecutor(uint256 time) public {
        // non-staked executor should be able to execute batch outside rounds. Should increase next epoch pool balance and take execution tax from executor
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - coordinator.getSlashingDuration() - 1
        );

        uint256 timeIntoRounds =
            coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() >= roundDuration);


        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        uint256 startBalance = token0.balanceOf(nonStakedExecutor);

        vm.warp(time);
        vm.prank(nonStakedExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, nonStakedExecutor, 0);
        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(token0.balanceOf(nonStakedExecutor), startBalance - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executionTax, "next epoch pool balance mismatch");
    }

    function test_InsideRoundExecutorDesignatedDoesntSupportModules(bytes32 seed) public {
        // as a non-desingated executor should be able to execute jobs in rounds with modules not supported by designated executor, but should not check in
        
        // first executor should be designated executor
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(1)))) % 2 == 0);

        // designated executor supports modules 0 and 1
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        // support modules 0 and 2
        vm.prank(secondExecutor);
        coordinator.stake((1 << 0) | (1 << 2));

        jobRegistry.setReturnExecutionModule(0);
        // module not supported by designated executor
        jobRegistry.setReturnFeeModule(2);

        coordinator.setEpoch(10);
        coordinator.setSeed(seed);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;
        // go to round 1
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() + coordinator.getRoundDuration() + coordinator.getRoundBuffer());
        vm.prank(secondExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, secondExecutor, 0);
        // check executorInfo is correct
        (uint256 balance,,,,, uint8 lastCheckinRound, uint96 lastCheckinEpoch,,,) = coordinator.executorInfo(secondExecutor);
        // should not change lastCheckinRound and lastCheckinEpoch since second executor is not designated
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
    }

    function test_InsideRoundsNonExecutor(uint256 time) public {
        // non-staked executor should be able to execute batch in rounds when job includes a module not supported by designated executor. Should increase protocol balance by executionTax.
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - coordinator.getSlashingDuration() - 1
        );

        // need to stake to avoid dividing by zero in batchExecute when there are 0 active executors
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        uint256 timeIntoRounds =
            coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() < roundDuration);


        jobRegistry.setReturnExecutionModule(0);
        // module not supported by designated executor
        jobRegistry.setReturnFeeModule(2);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        uint256 startBalance = token0.balanceOf(nonStakedExecutor);

        vm.warp(time);
        vm.prank(nonStakedExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, nonStakedExecutor, 0);
        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(token0.balanceOf(nonStakedExecutor), startBalance - executionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
        assertEq(coordinator.protocolBalance(), executionTax, "protocol balance mismatch");
    }


    function test_OutsideRoundZeroFeeWindowJobExecutor(uint256 time) public {
    // executing job in zero fee window should tax with zeroFeeExecutionTax. Tax is split between protocol and next pool
      time = bound(
          time,
          defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
          defaultEpochEndTime - 1
      );

      uint256 timeIntoRounds =
          coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
      vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() >= roundDuration);

      vm.prank(executor);
      coordinator.stake(modulesToRegister);
      uint256[] memory indices = new uint256[](1);
      indices[0] = 0;
      uint256[] memory gasLimits = new uint256[](1);
      gasLimits[0] = 500_000;

      jobRegistry.setJobsInZeroFeeWindow(true);

      vm.warp(time);
      vm.prank(executor);
      (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, executor, 0);
      (uint256 balance,,,,,,,,,) = coordinator.executorInfo(executor);
      assertEq(successfulExecutions, 1, "number of successful executions mismatch");
      assertEq(balance, stakingAmountPerModule * 2 - zeroFeeExecutionTax, "executor balance mismatch");
      assertEq(coordinator.getNextEpochPoolBalance(), zeroFeeExecutionTax / 2, "next epoch pool balance mismatch");
      assertEq(coordinator.protocolBalance(), zeroFeeExecutionTax / 2, "protocol balance mismatch");
    }

    function test_InsideRoundZeroFeeWindowJobExecutor(bytes32 seed) public {
        // executing job in zero fee window should tax with zeroFeeExecutionTax. Also designated executors registered modules should not matter
        // and should not set lastCheckinRound lastCheckinEpoch and increment executedJobsInRoundsOfEpoch

        // first executor is designated executor
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);
        // registering for same modules
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        jobRegistry.setJobsInZeroFeeWindow(true);

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(secondExecutor);
        (,, uint256 successfulExecutions) = coordinator.executeBatch(indices, gasLimits, secondExecutor, 0);

        (uint256 balance,,,,uint8 roundsCheckedInEpoch, uint8 lastCheckinRound, uint96 lastCheckinEpoch, uint96 executionsInRoundsInEpoch,,) = coordinator.executorInfo(secondExecutor);
        assertEq(successfulExecutions, 1, "number of successful executions mismatch");
        assertEq(balance, stakingAmountPerModule * 2 - zeroFeeExecutionTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), zeroFeeExecutionTax / 2, "next epoch pool balance mismatch");
        assertEq(coordinator.protocolBalance(), zeroFeeExecutionTax / 2, "protocol balance mismatch");
        assertEq(coordinator.getExecutedJobsInRoundsOfEpoch(), 0, "executed jobs in rounds of epoch mismatch");
        assertEq(roundsCheckedInEpoch, 0, "rounds checked in epoch mismatch");
        assertEq(lastCheckinRound, 0, "last checkin round mismatch");
        assertEq(lastCheckinEpoch, 0, "last checkin epoch mismatch");
        assertEq(executionsInRoundsInEpoch, 0, "executed jobs in rounds of epoch mismatch");
    }

    function test_GoingBelowMinimumStakeThresholdInEpochExecutor(uint256 time) public {
        // going below minimum stake threshold as executor in an epoch should deactivate the executor
        time = bound(time, defaultEpochEndTime - coordinator.getEpochDuration(), defaultEpochEndTime - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        // set balance to just above threshold
        coordinator.setExecutorBalance(coordinator.getStakingBalanceThresholdPerModule() * 2 + 1, executor);


        vm.warp(time);
        vm.prank(executor);
        coordinator.executeBatch(indices, gasLimits, executor, 0);

        (,bool active,,,,,,,,) = coordinator.executorInfo(executor);
        assertFalse(active, "executor should be deactivated");
    }

    function test_GoingBelowMinimumStakeThresholdOutsideEpochExecutor(uint256 time) public {
        // going below minimum stake threshold as executor outside an epoch should deactivate the executor
        vm.assume(time < defaultEpochEndTime - coordinator.getEpochDuration() || time >= defaultEpochEndTime);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        // set balance to just above threshold
        coordinator.setExecutorBalance(coordinator.getStakingBalanceThresholdPerModule() * 2 + 1, executor);


        vm.warp(time);
        vm.prank(executor);
        coordinator.executeBatch(indices, gasLimits, executor, 0);

        (,bool active,,,,,,,,) = coordinator.executorInfo(executor);
        assertFalse(active, "executor should be deactivated");
    }


}