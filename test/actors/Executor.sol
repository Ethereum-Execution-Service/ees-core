// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract Executor is Test {
    MockCoordinator coordinator;
    MockERC20 token;


    uint256 amountStaked;
    uint256 amountUnstaked;

    constructor(MockCoordinator _coordinator, MockERC20 _token) {
        coordinator = _coordinator;
        token = _token;
    }

    function stake() public {
        uint256 epochEndTime = coordinator.epochEndTime();
        // if we are in rounds or slashing phase, we warp forward to after
        if (
            block.timestamp >= epochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                && block.timestamp < epochEndTime
        ) {
            vm.warp(epochEndTime);
        }
        amountStaked += coordinator.getStakingAmount();
        coordinator.stake();
    }

    function unstake() public {
        // if we havent staked, stake
        if (amountStaked == 0) {
            stake();
        }

        // have to warp such that we are after the minimum staking period and not in reveal phase, execution rounds and slashing duration.
        uint256 epochEndTime = coordinator.epochEndTime();
        uint256 minimumStakingPeriod = coordinator.getMinimumStakingPeriod();
        (,,,,,, uint256 stakingTimestamp) = coordinator.executorInfo(msg.sender);
        uint256 minimumUnstakeTime = stakingTimestamp + minimumStakingPeriod;
        if (
            (block.timestamp >= epochEndTime - coordinator.getEpochDuration() + coordinator.getCommitPhaseDuration()
                && block.timestamp < epochEndTime) || block.timestamp < minimumUnstakeTime
        ) {
            vm.warp(epochEndTime > minimumUnstakeTime ? epochEndTime : minimumUnstakeTime);
        }

        (uint256 balance,,,,,,) = coordinator.executorInfo(msg.sender);
        amountUnstaked += balance;
        coordinator.unstake();
    }

    function topup(uint256 amount) public {
        // if we havent staked, stake
        if (amountStaked == 0) {
            stake();
        }
        // cannot be called during rounds and slashing phase
        // we bound amount to what we have in balance
        amount = bound(amount, 0, token.balanceOf(msg.sender) / 100);
        uint256 epochEndTime = coordinator.epochEndTime();
        if (
            block.timestamp >= epochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                && block.timestamp < epochEndTime
        ) {
            vm.warp(epochEndTime);
        }

        amountStaked += amount;
        coordinator.topup(amount);
    }

}
