// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the executeBatch function
 */
contract CoordinatorExecuteBatchTest is CoordinatorBaseTest {
  function test_ExecuteBatchInEpochOutsideRound(uint256 time) public {
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

    function test_ExecuteBatchNotDesignatedExecutorModuleSupported(bytes32 seed) public {
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

    function test_ExecuteBatchInRoundCheckIn(uint256 epochPoolBalance) public {
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
    }

    function test_ExecuteBatchAlreadyCheckedIn(uint256 time) public {
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
        coordinator.executeBatch(indices, gasLimits, executor, 0);
    }

    function test_ExecuteBatchInRoundNoCheckIn(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - coordinator.getSlashingDuration() - 1
        );
        uint256 timeIntoRounds =
            coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() < roundDuration);

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
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchExecutionReverts() public {
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

    function test_ExecuteBatchBeforeRounds(uint256 time) public {
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

    function test_ExecuteBatchAfterRounds(uint256 time) public {
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
}