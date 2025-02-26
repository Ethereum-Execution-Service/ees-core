// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the slashCommitter function
 */
contract CoordinatorSlashCommitterTest is CoordinatorBaseTest {
    function test_SlashCommitter(address slasher, uint256 time) public {
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        (uint256 startBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashCommitter(executor, slasher);
        (uint256 endBalanceSlasher,,,,,,,,,) = coordinator.executorInfo(slasher);

        (,, bool revealed) = coordinator.commitmentMap(executor);
        (uint256 balance, bool active,,,,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmountPerModule * 2 - commitSlashingAmountPerModule * 2, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(
            endBalanceSlasher, startBalanceSlasher + (commitSlashingAmountPerModule * 2) / 2, "slasher balance mismatch"
        );
    }

    function test_SlashCommitterNotExecutor(address slasher, uint256 time) public {
        // an un-staked (not registered executor) caller and recipient should be able to slash and receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashCommitter(executor, slasher);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);

        (,, bool revealed) = coordinator.commitmentMap(executor);
        (uint256 balance, bool active,,,,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmountPerModule * 2 - commitSlashingAmountPerModule * 2, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(
            endBalanceSlasher, startBalanceSlasher + (commitSlashingAmountPerModule * 2) / 2, "slasher balance mismatch"
        );
    }

    function test_SlashCommitterBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - coordinator.getSlashingDuration() - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(secondExecutor);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: 0, epoch: secondEpochNum, revealed: false}), executor
        );

        coordinator.setEpoch(epochNum);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.OldEpoch.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterCommitmentRevealed(address slasher) public {
        vm.assume(slasher != executor);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake(modulesToRegister);

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: true}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.prank(slasher);
        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.CommitmentRevealed.selector);
        coordinator.slashCommitter(executor, slasher);
    }
}
