// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract Executor is Test {
    MockCoordinator coordinator;

    uint256 public amountStaked;
    uint256 public amountUnstaked;

    constructor(MockCoordinator _coordinator) {
        coordinator = _coordinator;
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
        // have to warp such that we are after the minimum staking period and not in reveal phase, execution rounds and slashing duration.
        uint256 epochEndTime = coordinator.epochEndTime();
        uint256 minimumStakingPeriod = coordinator.getMinimumStakingPeriod();
        (,,,,,,, uint256 stakingTimestamp) = coordinator.executorInfo(address(this));

        uint256 minimumUnstakeTime = stakingTimestamp + minimumStakingPeriod;
        if (
            (block.timestamp >= epochEndTime - coordinator.getEpochDuration() + coordinator.getCommitPhaseDuration()
                && block.timestamp < epochEndTime) || block.timestamp < minimumUnstakeTime
        ) {
            vm.warp(epochEndTime > minimumUnstakeTime ? epochEndTime : minimumUnstakeTime);
        }

        (uint256 balance,,,,,,,) = coordinator.executorInfo(address(this));
        amountUnstaked += balance;
        coordinator.unstake();
    }

    function topup(uint256 amount) public {
        // cannot be called during rounds and slashing phase
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

    function executeBatch() public {
      // we have to see if were in rounds
      // then which round were in
      // we use mock contract to alter designated to this executor
      // with slashing we do somethign similar, we dont actually commit/reveal, we just alter state such that someone can be slashed


      uint256[] memory jobIds = new uint256[](1);
      jobIds[0] = 0;
      uint256[] memory gasLimits = new uint256[](1);
      gasLimits[0] = 200_000;


      // if were not in rounds, we can just execute
      // if we are in rounds, we have to see which round we are in

      if (block.timestamp < coordinator.epochEndTime() - coordinator.getSlashingDuration() && block.timestamp >= coordinator.epochEndTime() - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()) {
        // we are in rounds
        uint256 timeIntoRounds = coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (coordinator.epochEndTime() - block.timestamp);
        bool inRound = timeIntoRounds % coordinator.getTotalRoundDuration() < coordinator.getRoundDuration();

        if (inRound) {
          // figure out which round we are in
          uint8 round = uint8(timeIntoRounds / coordinator.getTotalRoundDuration());
          // force designation in this round to this executor
          // we can only do this by finding an appropriate seed and set it via mock coordinator
          // thus we have to loop thorugh different seeds until we find one that works
          // we have up update seed by hashing until we find one that works. The expected number of iterations is the number of active executors
          bytes32 seed = coordinator.seed();
          while (true) {
            uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, round))) % coordinator.numberOfActiveExecutors();
            if (coordinator.activeExecutors(executorIndex) == address(this)) break;
            seed = keccak256(abi.encodePacked(seed));
          }
          coordinator.setSeed(seed);

          // now we can execute
          coordinator.executeBatch(jobIds, gasLimits, address(this));
        } else {
          // we are not in round, just execute
          coordinator.executeBatch(jobIds, gasLimits, address(this));
        }
      } else {
        // we are not in rounds, just execute
        coordinator.executeBatch(jobIds, gasLimits, address(this));
      }
    }

    function slashCommitter(address _executor) public {
      // check we are in time bounds, if not, warp to slashing phase
      uint256 epochEndTime = coordinator.epochEndTime();
      if (block.timestamp < epochEndTime - coordinator.getSlashingDuration()) {
        vm.warp(epochEndTime - coordinator.getSlashingDuration());
      } else if (block.timestamp >= epochEndTime) {
        return;
      }

      // we set committer info
      coordinator.setCommitment(ICoordinator.CommitData({
        commitment: 0,
        epoch: coordinator.epoch(),
        revealed: false
      }), _executor);

      coordinator.slashCommitter(_executor, address(this));
    }

    function slashInactiveExecutor(address _executor, uint8 round) public {
      // check we are in time bounds, if not, warp to slashing phase
      uint256 epochEndTime = coordinator.epochEndTime();
      if (block.timestamp < epochEndTime - coordinator.getSlashingDuration()) {
        vm.warp(epochEndTime - coordinator.getSlashingDuration());
      } else if (block.timestamp >= epochEndTime) {
        return;
      }

      // we have to set the seed such that the executor to slash is actually designated in the given round
      bytes32 seed = coordinator.seed();
      while (true) {
        uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, round))) % coordinator.numberOfActiveExecutors();
        if (coordinator.activeExecutors(executorIndex) == _executor) break;
        seed = keccak256(abi.encodePacked(seed));
      }
      coordinator.setSeed(seed);

      // we artificially set checkin to false for the given executor at the specific round
      uint192 epoch = coordinator.epoch();
      if (epoch > 0) {
        coordinator.setLastCheckin(round, 0, _executor);
      } else {
        coordinator.setLastCheckin(round, 1, _executor);
      }
      coordinator.slashInactiveExecutor(_executor, round, address(this));
    }
}
