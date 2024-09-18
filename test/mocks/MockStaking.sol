// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Staking} from "../../src/Staking.sol";
/// @author Victor Brevig

contract MockStaking is Staking {
    constructor(StakingSpec memory _spec) Staking(_spec) {}

    function setSeed(bytes32 _seed) public {
        seed = _seed;
    }

    function setExecutedRound(uint256 _index, bool _value) public {
        require(_index < executedRounds.length, "MockStaking: index out of bounds");
        executedRounds[_index] = _value;
    }

    function setStakerInfo(StakerInfo memory _stakerInfo, address _staker) public {
        stakerInfo[_staker] = _stakerInfo;
    }

    function setEpochEndTime(uint256 _epochEndTime) public {
        epochEndTime = _epochEndTime;
    }

    function setCommitment(CommitData memory _commitment, address _executor) public {
        commitmentMap[_executor] = _commitment;
    }

    function setEpoch(uint248 _epoch) public {
        epoch = _epoch;
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
}
