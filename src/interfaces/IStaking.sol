// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    struct StakerInfo {
        uint256 balance;
        bool active;
        bool initialized;
        uint40 arrayIndex;
        uint192 latestExecutedEpoch;
    }

    struct CommitData {
        bytes32 commitment;
        uint192 epoch;
        bool revealed;
    }

    struct StakingSpec {
        address stakingToken;
        uint256 stakingAmount;
        uint256 stakingBalanceThreshold;
        uint256 inactiveSlashingAmount;
        uint256 commitSlashingAmount;
        uint8 roundDuration;
        uint8 roundsPerEpoch;
        uint8 roundBuffer;
        uint8 commitPhaseDuration;
        uint8 revealPhaseDuration;
        uint8 slashingDuration;
    }

    event EpochInitiated(uint192 epoch);

    error NotActiveStaker();
    error AlreadyStaked();
    error RoundExecuted();
    error WrongNumberOfRandomWords();
    error CommitmentRevealed();
    error InvalidBlockTime();
    error OldEpoch();
    error InvalidSignature();
    error WrongCommitment();
    error InvalidSignatureLength();
    error StakerNotSelectedForRound();
    error RoundExceedingTotal();
}
