// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    struct StakerInfo {
        uint256 balance;
        bool active;
        bool initialized;
        uint40 arrayIndex;
    }

    struct StakingSpec {
        address stakingToken;
        uint256 stakingAmount;
        uint256 stakingBalanceThreshold;
        uint256 slashingAmount;
        uint8 roundDuration;
        uint8 roundsPerEpoch;
        uint8 slashingWindow;
        uint8 roundBuffer;
        uint8 epochBuffer;
    }

    error NotAStaker();
    error EpochAlreadyRequested();
    error EpochNotDone();
    error OnlyCoordinator();
    error RequestAlreadyFulfilled();
    error AlreadyStaked();
    error RoundExecuted();
    error SlashingWindowOver();
    error WrongNumberOfRandomWords();
}
