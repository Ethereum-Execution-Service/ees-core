// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoordinator {
    struct Executor {
        // slot 0
        uint256 balance;
        // slot 1
        bool active;
        bool initialized;
        uint32 arrayIndex;
        uint8 roundsCheckedInEpoch;
        uint8 lastCheckinRound;
        uint96 lastCheckinEpoch;
        uint96 executionsInRoundsInEpoch;
        // slot 2
        uint256 lastRegistrationTimestamp;
        // slot 3
        uint256 registeredModules;
    }

    struct CommitData {
        bytes32 commitment;
        uint192 epoch;
        bool revealed;
    }

    struct InitSpec {
        address stakingToken;
        uint256 stakingAmountPerModule;
        uint256 minimumRegistrationPeriod;
        uint256 stakingBalanceThresholdPerModule;
        uint256 inactiveSlashingAmountPerModule;
        uint256 commitSlashingAmountPerModule;
        uint8 roundDuration;
        uint8 roundsPerEpoch;
        uint8 roundBuffer;
        uint8 commitPhaseDuration;
        uint8 revealPhaseDuration;
        uint8 slashingDuration;
        uint256 executionTax;
        uint256 zeroFeeExecutionTax;
        uint256 protocolPoolCutBps;
    }

    function executeBatch(
        uint256[] calldata _indices,
        uint256[] calldata _gasLimits,
        address _feeRecipient,
        uint8 _jobRegistryIndex
    ) external returns (uint256 standardTax, uint256 zeroFeeTax, uint256 successfulExecutions);
    function stake(uint256 _modulesBitset) external returns (uint256 stakingAmount);
    function unstake() external;
    function topup(uint256 _amount) external;
    function slashInactiveExecutor(address _executor, uint8 _round, address _recipient) external;
    function slashCommitter(address _executor, address _recipient) external;
    function initiateEpoch() external;
    function commit(bytes32 _commitment) external;
    function reveal(bytes calldata _signature) external;

    event BatchExecution(uint8 jobRegistryIndex, uint256 standardTax, uint256 zeroFeeTax);
    event EpochInitiated(uint192 epoch, uint256 previousEpochPoolDistributed, uint256 protocolCut);
    event SlashInactiveExecutor(
        address indexed executor, address indexed slasher, uint192 indexed epoch, uint8 round, uint256 amount
    );
    event SlashCommitter(address indexed executor, address indexed slasher, uint192 indexed epoch, uint256 amount);
    event Commitment(address indexed executor, uint192 indexed epoch);
    event Reveal(address indexed executor, uint192 indexed epoch, bytes32 newSeed);
    event CheckIn(address indexed executor, uint192 indexed epoch, uint8 round);
    event ExecutorDeactivated(address indexed executor);
    event ExecutorActivated(address indexed executor);
    event ModulesRegistered(address indexed executor, uint256 indexed modulesBitset);
    event ModulesDeregistered(address indexed executor, uint256 indexed modulesBitset);

    error NotActiveExecutor();
    error NotInitializedExecutor();
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
    error MinimumRegistrationPeriodNotOver();
    error FinalBalanceBelowMinimum();
    error ExecutorNotRegisteredForModules();
    error JobRegistryNotSet();
    error DesignatedExecutorSupportsModules();
}
