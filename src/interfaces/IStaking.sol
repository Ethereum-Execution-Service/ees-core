// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    struct StakerInfo {
        uint256 balance;
        bool active;
        bool initialized;
        uint40 arrayIndex;
    }

    struct CommitData {
        bytes32 commitment;
        uint256 epoch;
        bool revealed;
    }

    struct StakingSpec {
        address stakingToken;
        uint256 stakingAmount;
        uint256 stakingBalanceThreshold;
        uint256 slashingAmount;
        uint8 roundDuration;
        uint8 roundsPerEpoch;
        uint8 roundBuffer;
        uint8 commitPhaseDuration;
        uint8 revealPhaseDuration;
    }

    error NotAStaker();
    error AlreadyStaked();
    error RoundExecuted();
    error WrongNumberOfRandomWords();
    error CommitmentRevealed();
    error InvalidBlockNumber();
    error OldEpoch();
    error InvalidSignature();
    error WrongCommitment();
    error NotInBufferOfRound();
    error InvalidSignatureLength();
}
