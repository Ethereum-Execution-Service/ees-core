// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the initiateEpoch function
 */
contract CoordinatorInitiateEpochTest is CoordinatorBaseTest {
    function test_InitiateEpoch(address caller, uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);
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
}
