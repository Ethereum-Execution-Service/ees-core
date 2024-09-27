// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExecutionManager {
    struct Executor {
        uint256 balance;
        bool active;
        bool initialized;
        uint40 arrayIndex;
        uint8 lastCheckinRound;
        uint192 lastCheckinEpoch;
    }

    struct CommitData {
        bytes32 commitment;
        uint192 epoch;
        bool revealed;
    }

    struct InitSpec {
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
        uint256 executorTax;
        uint256 protocolTax;
    }

    event EpochInitiated(uint192 epoch);

    error NotActiveExecutor();
    error AlreadyStaked();
    error RoundExecuted();
    error WrongNumberOfRandomWords();
    error CommitmentRevealed();
    error InvalidBlockTime();
    error OldEpoch();
    error InvalidSignature();
    error WrongCommitment();
    error InvalidSignatureLength();
    error ExecutorNotSelectedForRound();
    error RoundExceedingTotal();
    error AlreadyCheckedIn();
    error CheckInOutsideRound();
}
