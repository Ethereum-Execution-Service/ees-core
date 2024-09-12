// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Staking} from "../../src/Staking.sol";
/// @author Victor Brevig

contract MockStaking is Staking {
    constructor(StakingSpec memory _spec, uint256 _subscriptionId, address _vrfCoordinator)
        Staking(_spec, _subscriptionId, _vrfCoordinator)
    {}

    function setSelectedIndex(uint256 _index, uint40 _value) public {
        require(_index < selectedIndices.length, "MockStaking: index out of bounds");
        selectedIndices[_index] = _value;
    }

    function setExecutedRound(uint256 _index, bool _value) public {
        require(_index < executedRounds.length, "MockStaking: index out of bounds");
        executedRounds[_index] = _value;
    }

    function setStakerInfo(StakerInfo memory _stakerInfo, address _staker) public {
        stakerInfo[_staker] = _stakerInfo;
    }

    function setEpochEndBlock(uint256 _epochEndBlock) public {
        epochEndBlock = _epochEndBlock;
    }
}
