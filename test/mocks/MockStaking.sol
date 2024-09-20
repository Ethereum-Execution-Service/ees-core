// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Staking} from "../../src/Staking.sol";
/// @author Victor Brevig

contract MockStaking is Staking {
    constructor(StakingSpec memory _spec) Staking(_spec) {}

    function setSeed(bytes32 _seed) public {
        seed = _seed;
    }

    function setStakerInfo(StakerInfo memory _stakerInfo, address _staker) public {
        stakerInfo[_staker] = _stakerInfo;
    }

    function setEpochEndTime(uint256 _epochEndTime) public {
        epochEndTime = _epochEndTime;
    }

    function getSlashingDuration() public view returns (uint256) {
        return slashingDuration;
    }

    function setCommitment(CommitData memory _commitment, address _executor) public {
        commitmentMap[_executor] = _commitment;
    }

    function setEpoch(uint192 _epoch) public {
        epoch = _epoch;
    }

    function setNumberOfActiveStakers(uint40 _numberOfActiveStakers) public {
        numberOfActiveStakers = _numberOfActiveStakers;
    }

    function getActiveStakersLength() public view returns (uint256) {
        return activeStakers.length;
    }

    function getEpochDuration() public view returns (uint256) {
        return epochDuration;
    }

    function getSelectionPhaseDuration() public view returns (uint256) {
        return selectionPhaseDuration;
    }

    function getTotalRoundDuration() public view returns (uint256) {
        return totalRoundDuration;
    }

    function getNumberOfActiveStakers() public view returns (uint40) {
        return numberOfActiveStakers;
    }
}
