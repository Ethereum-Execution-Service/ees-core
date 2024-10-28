// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoordinator {
    struct Executor {
        uint256 balance;
        bool active;
        bool initialized;
        uint40 arrayIndex;
        uint8 lastCheckinRound;
        uint192 lastCheckinEpoch;
        uint256 stakingTimestamp;
    }

    struct CommitData {
        bytes32 commitment;
        uint192 epoch;
        bool revealed;
    }

    struct InitSpec {
        address stakingToken;
        uint256 stakingAmount;
        uint256 minimumStakingPeriod;
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

    function executeBatch(
        uint256[] calldata _indices,
        uint256[] calldata _gasLimits,
        address _feeRecipient,
        bool _checkIn
    ) external returns (uint256[] memory failedIndices);
    function stake() external;
    function unstake() external;
    function topup(uint256 _amount) external;
    function slashInactiveExecutor(address _executor, uint8 _round, address _recipient) external;
    function slashCommitter(address _executor, address _recipient) external;
    function initiateEpoch() external;
    function commit(bytes32 _commitment) external;
    function reveal(bytes calldata _signature) external;

    event BatchExecution(uint256[] failedIndices);
    event EpochInitiated(uint192 epoch);
    event SlashInactiveExecutor(
        address indexed executor, address indexed slasher, uint192 indexed epoch, uint8 round, uint256 amount
    );
    event SlashCommitter(address indexed executor, address indexed slasher, uint192 indexed epoch, uint256 amount);
    event Commitment(address indexed executor, uint192 indexed epoch);
    event Reveal(address indexed executor, uint192 indexed epoch, bytes32 newSeed);
    event CheckIn(address indexed executor, uint192 indexed epoch, uint8 round);

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
    error MinimumStakingPeriodNotOver();
    error TopupBelowMinimum();
}
