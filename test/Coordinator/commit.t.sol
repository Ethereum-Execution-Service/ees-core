// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the commit function
 */
contract CoordinatorCommitTest is CoordinatorBaseTest {
    function test_Commit(bytes32 commitment, uint192 epoch, uint256 time) public {
        // should go from defaultEpochEndTime - coordinator.getEpochDuration() to defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration(),
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration - 1
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        coordinator.setEpoch(epoch);
        vm.warp(time);
        vm.prank(executor);
        coordinator.commit(commitment);

        (bytes32 commitmentSet, uint192 epochSet, bool revealedSet) = coordinator.commitmentMap(executor);
        assertEq(commitmentSet, commitment, "commitment mismatch");
        assertEq(epochSet, epoch, "epoch mismatch");
        assertFalse(revealedSet, "revealed mismatch");
    }

    function test_CommitAfterCommitmentPeriod(uint256 time) public {
        time =
            bound(time, defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration, type(uint256).max);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.commit(0);
    }

    function test_CommitNotAnExecutor(address caller) public {
        vm.prank(caller);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration());
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.commit(0);
    }
}
