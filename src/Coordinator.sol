// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ICoordinator} from "./interfaces/ICoordinator.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";
import {TaxHandler} from "./TaxHandler.sol";
import {ModuleRegistry} from "./ModuleRegistry.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";

/**
 * __/\\\\\\\\\\\\\\\__/\\\\\\\\\\\\\\\_____/\\\\\\\\\\\___
 *  _\/\\\///////////__\/\\\///////////____/\\\/////////\\\_
 *   _\/\\\_____________\/\\\______________\//\\\______\///__
 *    _\/\\\\\\\\\\\_____\/\\\\\\\\\\\_______\////\\\_________
 *     _\/\\\///////______\/\\\///////___________\////\\\______
 *      _\/\\\_____________\/\\\_____________________\////\\\___
 *       _\/\\\_____________\/\\\______________/\\\______\//\\\__
 *        _\/\\\\\\\\\\\\\\\_\/\\\\\\\\\\\\\\\_\///\\\\\\\\\\\/___
 *         _\///////////////__\///////////////____\///////////_____
 *
 * @title Coordinator
 * @notice Coordinates executors for job execution, manages staking, slashing, and epoch-based reward distribution
 * @dev Inherits from TaxHandler for tax management and ReentrancyGuard for reentrancy protection.
 *      Manages executor lifecycle, commit-reveal scheme for randomness, and designated executor selection.
 */
contract Coordinator is ICoordinator, TaxHandler, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /// @notice Array of registered job registry addresses
    address[] public jobRegistries;

    /// @notice Mapping to check if an address is a registered job registry
    mapping(address => bool) public isJobRegistry;

    /// @notice Current seed used for designated executor selection
    /// @dev Updated during reveal phase via commit-reveal scheme
    bytes32 public seed;

    /// @notice Current epoch number
    uint192 public epoch;

    /// @notice Timestamp when the current epoch ends
    uint256 public epochEndTime;

    /// @notice Number of currently active executors eligible for designation
    uint32 public numberOfActiveExecutors;

    /// @notice ERC20 token used for staking
    address internal immutable stakingToken;

    /// @notice Amount of tokens required to stake per module when registering
    uint256 internal immutable stakingAmountPerModule;

    /// @notice Minimum time period an executor must remain registered before unstaking
    uint256 internal immutable minimumRegistrationPeriod;

    /// @notice Minimum staking balance per module required to remain active
    /// @dev If balance falls below this threshold, executor is deactivated
    uint256 internal immutable stakingBalanceThresholdPerModule;

    /// @notice Amount slashed per module for inactive executors who don't execute in their designated round
    uint256 internal immutable inactiveSlashingAmountPerModule;

    /// @notice Amount slashed per module for executors who commit but don't reveal
    uint256 internal immutable commitSlashingAmountPerModule;

    /// @notice Number of rounds per epoch
    uint8 internal immutable roundsPerEpoch;

    /// @notice Pool balance for the current epoch (distributed to executors)
    uint256 public epochPoolBalance;

    /// @notice Pool balance accumulated for the next epoch
    uint256 public nextEpochPoolBalance;

    /// @notice Protocol balance (withdrawable by owner)
    uint256 public protocolBalance;

    /// @notice Duration of each round in seconds
    uint8 internal immutable roundDuration;

    /// @notice Buffer time between rounds in seconds
    uint8 internal immutable roundBuffer;

    /// @notice Total duration of an epoch in seconds
    uint16 internal immutable epochDuration;

    /// @notice Duration of commit phase in seconds
    uint8 internal immutable commitPhaseDuration;

    /// @notice Duration of reveal phase in seconds
    uint8 internal immutable revealPhaseDuration;

    /// @notice Total duration of selection phase (commit + reveal) in seconds
    uint8 internal immutable selectionPhaseDuration;

    /// @notice Total duration of a round including buffer in seconds
    uint8 internal immutable totalRoundDuration;

    /// @notice Duration of slashing window in seconds
    uint8 internal immutable slashingDuration;

    /// @notice Array of active executor addresses
    /// @dev Maintains invariant: activeExecutors[0..numberOfActiveExecutors-1] are all valid executors
    address[] public activeExecutors;

    /// @notice Mapping from executor address to their executor information
    mapping(address => Executor) public executorInfo;

    /// @notice Total number of jobs executed during rounds in the current epoch (excluding zero-fee jobs)
    uint96 public executedJobsInRoundsOfEpoch;

    /// @notice Addresses of designated executors who executed jobs during rounds this epoch
    /// @dev Resets every epoch. Used for reward distribution.
    address[] public poolCutReceivers;

    /// @notice Mapping from executor address to their commit-reveal data
    mapping(address => CommitData) public commitmentMap;

    /**
     * @notice Initializes the Coordinator contract with configuration parameters
     * @dev Validates configuration parameters and sets up initial state. All time durations are in seconds.
     * @param _spec Configuration specification containing all system parameters
     * @param _owner Address that will own the contract (can update taxes and add modules)
     * @custom:requirements
     *   - stakingBalanceThresholdPerModule <= stakingAmountPerModule
     *   - inactiveSlashingAmountPerModule + commitSlashingAmountPerModule <= stakingBalanceThresholdPerModule
     *   - roundsPerEpoch > 0 and < 256
     *   - totalRoundDuration > 0
     */
    constructor(InitSpec memory _spec, address _owner)
        TaxHandler(_owner, _spec.executionTax, _spec.zeroFeeExecutionTax, _spec.protocolPoolCutBps)
    {
        require(
            _spec.stakingBalanceThresholdPerModule <= _spec.stakingAmountPerModule,
            "Staking: threshold must be less than or equal to staking amount"
        );
        require(
            uint256(_spec.roundsPerEpoch) * uint256(_spec.roundDuration + _spec.roundBuffer)
                <= type(uint8).max * uint256(_spec.roundDuration + _spec.roundBuffer),
            "Staking: rounds calculation may overflow"
        );
        totalRoundDuration = _spec.roundDuration + _spec.roundBuffer;
        require(totalRoundDuration > 0, "Staking: round duration and buffer must be greater than 0");

        stakingToken = _spec.stakingToken;
        stakingAmountPerModule = _spec.stakingAmountPerModule;
        minimumRegistrationPeriod = _spec.minimumRegistrationPeriod;
        stakingBalanceThresholdPerModule = _spec.stakingBalanceThresholdPerModule;
        inactiveSlashingAmountPerModule = _spec.inactiveSlashingAmountPerModule;
        commitSlashingAmountPerModule = _spec.commitSlashingAmountPerModule;
        require(
            inactiveSlashingAmountPerModule + commitSlashingAmountPerModule <= stakingBalanceThresholdPerModule,
            "Staking: invalid slashing amounts"
        );
        require(_spec.roundsPerEpoch > 0, "Staking: rounds per epoch must be greater than 0");
        require(_spec.roundsPerEpoch < 256, "Staking: rounds per epoch must be less than 256");
        roundDuration = _spec.roundDuration;
        roundsPerEpoch = _spec.roundsPerEpoch;
        roundBuffer = _spec.roundBuffer;
        slashingDuration = _spec.slashingDuration;
        selectionPhaseDuration = _spec.commitPhaseDuration + _spec.revealPhaseDuration;
        epochDuration = uint16(selectionPhaseDuration) + uint16(totalRoundDuration) * uint16(roundsPerEpoch)
            + uint16(slashingDuration);
        commitPhaseDuration = _spec.commitPhaseDuration;
        revealPhaseDuration = _spec.revealPhaseDuration;
        epochEndTime = block.timestamp;
    }

    /**
     * @notice Executes a batch of jobs from the specified job registry
     * @dev During designated rounds, only the selected executor can execute and pays no executor tax.
     *      Outside rounds, anyone can execute but must pay execution tax. Failed job executions don't revert the entire batch.
     * @param _indices Array of job indices to execute
     * @param _gasLimits Array of gas limits for each job execution (must match _indices length)
     * @param _feeRecipient Address to receive execution fees from job sponsors
     * @param _jobRegistryIndex Index of the job registry in the jobRegistries array
     * @return standardTax Total execution tax paid for non-zero-fee jobs
     * @return zeroFeeTax Total execution tax paid for zero-fee window jobs
     * @return successfulExecutions Total number of successfully executed jobs
     * @custom:emits BatchExecution event with job registry index, taxes, and round status
     * @custom:emits CheckIn event if designated executor checks in for the first time in a round
     * @custom:emits ExecutorDeactivated event if executor balance falls below threshold
     */
    function executeBatch(
        uint256[] calldata _indices,
        uint256[] calldata _gasLimits,
        address _feeRecipient,
        uint8 _jobRegistryIndex
    ) public override nonReentrant returns (uint256, uint256, uint96) {
        Executor memory executor = executorInfo[msg.sender];

        // *** IN ROUND CHECKS ***
        bool inRound;
        uint8 round;
        uint256 designatedExecutorModules;
        address designatedExecutor;
        if (
            block.timestamp < epochEndTime - slashingDuration
                && block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
        ) {
            // in alternating open competition and designated rounds part of the epoch
            uint256 timeIntoRounds;
            unchecked {
                // safe given that 1) epochEndTime > block.timestamp and 2) block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                timeIntoRounds = epochDuration - selectionPhaseDuration - (epochEndTime - block.timestamp);
                // totalRoundDuration is > 0 becasue of constructor check on totalRoundDuration
                inRound = timeIntoRounds % totalRoundDuration < roundDuration && numberOfActiveExecutors > 0;
            }

            if (inRound) {
                unchecked {
                    // totalRoundDuration is > 0 because of constructor check on totalRoundDuration
                    // timeIntoRounds / totalRoundDuration will not overflow uint8 becasue of constructor check
                    round = uint8(timeIntoRounds / totalRoundDuration);
                }
                uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, round))) % numberOfActiveExecutors;
                designatedExecutor = activeExecutors[executorIndex];
                designatedExecutorModules = executorInfo[designatedExecutor].registeredModules;
            }
        }

        // *** JOB REGISTRY EXECUTION CALLS ***
        address jobRegistryCache = jobRegistries[_jobRegistryIndex];
        uint256 indicesLength = _indices.length;
        uint16 epochDurationCache = epochDuration;
        uint96 executionCount;
        uint96 executionCountZeroFee;
        assembly {
            // Get the current free memory pointer
            let inputPtr := mload(0x40)

            // the next 3 slots (0x60 bytes) are reserved for the function selector, index, and gas limit
            // function selector doesnt change, so we can store it in memory once
            mstore(inputPtr, shl(224, 0xc032dc30)) // Function selector for execute(uint256,address)

            let i := 0

            // Allocate memory for return data (5 values * 32 bytes = 160 bytes)
            let returnDataPtr := mload(0x40)

            // Update free memory pointer
            mstore(0x40, add(returnDataPtr, 0xA0)) // advance by 160 bytes (5 * 32)

            let epochStartTime := sub(sload(epochEndTime.slot), epochDurationCache)

            for {} lt(i, indicesLength) {} {
                let index := calldataload(add(_indices.offset, mul(i, 0x20)))
                let gasLimit := calldataload(add(_gasLimits.offset, mul(i, 0x20)))

                mstore(add(inputPtr, 0x04), index)
                mstore(add(inputPtr, 0x24), _feeRecipient)

                let success :=
                    call(
                        gasLimit, // gas
                        jobRegistryCache, // address
                        0, // value
                        inputPtr, // input memory
                        0x44, // input size
                        returnDataPtr, // output memory
                        0xC0 // output size (6 * 32 bytes)
                    )

                if iszero(success) {
                    i := add(i, 1)
                    continue
                }

                // check if in zero fee window
                let inZeroFeeWindow := mload(add(returnDataPtr, 0x80)) // 5th word

                switch inZeroFeeWindow
                case 1 {
                    // job is in zero fee window
                    executionCountZeroFee := add(executionCountZeroFee, 1)
                }
                case 0 {
                    // job is not in zero fee window, have to perform checks
                    executionCount := add(executionCount, 1)

                    // Verify the executor is registered for both modules
                    if inRound {
                        // Load the execution module and fee module from the last two 32-byte words
                        let executionModuleId := and(mload(add(returnDataPtr, 0x40)), 0xFF) // 3th word
                        let feeModuleId := and(mload(add(returnDataPtr, 0x60)), 0xFF) // 4th word
                        // Check if executor is registered for both modules
                        let requiredModules := or(shl(1, executionModuleId), shl(1, feeModuleId))

                        switch eq(caller(), designatedExecutor)
                        case 1 {
                            // If we ARE the designated executor, we must support BOTH modules
                            if iszero(eq(and(designatedExecutorModules, requiredModules), requiredModules)) {
                                // Error selector for ExecutorNotRegisteredForModules()
                                let free_mem_ptr := mload(0x40)
                                mstore(free_mem_ptr, 0xff1edc1d00000000000000000000000000000000000000000000000000000000)
                                revert(free_mem_ptr, 0x04)
                            }
                        }
                        case 0 {
                            // If we are NOT the designated executor, designated executor must NOT support at least one module
                            if eq(and(designatedExecutorModules, requiredModules), requiredModules) {
                                // Error selector for DesignatedExecutorSupportsModules()
                                let free_mem_ptr := mload(0x40)
                                mstore(free_mem_ptr, 0x7738dd2200000000000000000000000000000000000000000000000000000000)
                                revert(free_mem_ptr, 0x04)
                            }
                        }
                    }
                }
                i := add(i, 1)
            }
        }

        // *** TAXING AND POOL BALANCE UPDATE ***
        uint256 totalTax;
        uint256 standardTax;
        uint256 zeroFeeTax;
        uint256 newBalance = executor.balance;
        if (executionCount > 0) {
            // handle normal tax for jobs not in zero fee window and update pool and protocol balances
            unchecked {
                // standardTax is never greater than uint256 max value realistically
                standardTax = executionTax * executionCount;

                // next epoch pool balance and protocol balance will never exceed uint256 max value since there are not enough tokens in existence
                // during designated rounds, tax goes to protocol balance.
                // otherwise, tax goes to next epoch pool balance.
                // increment executedJobsInRoundsOfEpoch only if we are in a round
                if (inRound) {
                    executedJobsInRoundsOfEpoch += executionCount;
                    protocolBalance += standardTax;
                } else {
                    nextEpochPoolBalance += standardTax;
                }
            }
        }
        if (executionCountZeroFee > 0) {
            // handle zero fee tax - update pool and protocol balances
            unchecked {
                // totalTax is never greater than uint256 max value realistically
                zeroFeeTax = zeroFeeExecutionTax * executionCountZeroFee;
                // halfZeroTax can never be greater than zeroFeeTax
                uint256 halfZeroFeeTax = zeroFeeTax / 2;
                // split zero fee tax between pool and protocol
                nextEpochPoolBalance += halfZeroFeeTax;
                protocolBalance += zeroFeeTax - halfZeroFeeTax;
            }
        }

        // *** TAX TRANSFER ***
        unchecked {
            totalTax = standardTax + zeroFeeTax;
        }
        if (totalTax > 0) {
            if (executor.initialized) {
                // if executor is initialized, use internal balance
                newBalance = (executorInfo[msg.sender].balance -= totalTax);
            } else {
                ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), totalTax);
            }
        }
        // *** DESIGNATED EXECUTOR UPDATES ***
        if (inRound && designatedExecutor == msg.sender) {
            if (!executor.active) revert NotActiveExecutor();

            bool checkInEpoch = executor.lastCheckinEpoch != epoch;
            bool checkInRound = executor.lastCheckinRound != round;

            // add to poolCutReceivers if this is first time executor checks in this epoch and executionCount > 0
            if (checkInEpoch && executionCount > 0) {
                poolCutReceivers.push(msg.sender);
            }

            // check that this is first time in this epoch and round that caller is checking in
            if (checkInEpoch || checkInRound) {
                // set lastCheckinEpoch to epoch and lastCheckinRound to round and increase executionsInRoundsInEpoch by executionCount in one storage write (they reside in same slot)
                assembly {
                    let epochValue := sload(epoch.slot)
                    let slot := executorInfo.slot
                    mstore(0x00, caller())
                    mstore(0x20, slot)
                    let executorSlot := keccak256(0x00, 0x40)
                    let currentValue := sload(add(executorSlot, 1))

                    // Preserve first 6 bytes (active, initialized, arrayIndex)
                    let preservedBits := and(currentValue, 0xFFFFFFFFFFFF)

                    // Get current roundsCheckedInEpoch (1 byte after first 6 bytes)
                    let currentRoundsChecked := and(shr(48, currentValue), 0xFF)
                    // Increment roundsCheckedInEpoch by 1
                    let newRoundsChecked := add(currentRoundsChecked, 1)

                    // Get current executionsInEpochCreatedBeforeEpoch value
                    let currentExecutions := shr(160, currentValue)
                    // Add new executions to it
                    let newExecutions := add(currentExecutions, executionCount)

                    // Pack values:
                    // [0-47]: preserved bits (active, initialized, arrayIndex) (6 bytes)
                    // [48-55]: roundsCheckedInEpoch (1 byte)
                    // [56-63]: lastCheckinRound (1 byte)
                    // [64-159]: lastCheckinEpoch (12 bytes)
                    // [160-255]: executionsInEpochCreatedBeforeEpoch (12 bytes)
                    let packedValue :=
                        or(
                            preservedBits,
                            or(
                                shl(48, newRoundsChecked),
                                or(shl(56, round), or(shl(64, epochValue), shl(160, newExecutions)))
                            )
                        )
                    sstore(add(executorSlot, 1), packedValue)
                }
                emit CheckIn(msg.sender, epoch, round);
            } else if (executionCount > 0) {
                // increment executions of jobs created before epoch. We dont update check in data
                executorInfo[msg.sender].executionsInRoundsInEpoch += executionCount;
            }
        }
        // *** BALANCE THRESHOLD CHECK AND POTENTIAL DEACTIVATION ***
        // check if executor balance is below threshold and deactivate if true
        if (
            executor.active && newBalance < stakingBalanceThresholdPerModule * _countModules(executor.registeredModules)
        ) {
            (address deactivatedExecutor, address lastExecutor) = _deactivateExecutor(executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = executor.arrayIndex;
            executorInfo[msg.sender].active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }

        emit BatchExecution(_jobRegistryIndex, standardTax, zeroFeeTax, inRound);
        return (standardTax, zeroFeeTax, executionCount + executionCountZeroFee);
    }

    /**
     * @notice Stakes tokens and activates the executor to be eligible for job execution
     * @dev Transfers staking tokens from caller and adds executor to activeExecutors array.
     *      Executor must register for at least 2 modules. Cannot be called during rounds or slashing window.
     * @param _modulesBitset Bitset representing which modules to register for (bit position = module index)
     * @return stakingAmount Total amount of tokens staked (stakingAmountPerModule * number of modules)
     * @custom:emits ModulesRegistered event with executor address and registered modules bitset
     * @custom:emits ExecutorActivated event when executor is successfully activated
     */
    function stake(uint256 _modulesBitset) public override returns (uint256 stakingAmount) {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration && block.timestamp < epochEndTime)
        {
            revert InvalidBlockTime();
        }
        if (executorInfo[msg.sender].initialized) revert AlreadyStaked();

        // *** MODULE REGISTRATION CHECK ***
        // only allow registration for existing modules
        uint256 validModules = _modulesBitset & _getValidModulesMask();
        uint256 numberOfModules = _countModules(validModules);
        if (numberOfModules < 2) revert NumberOfRegisteredModulesBelowMinimum();

        // *** STAKING ***
        stakingAmount = stakingAmountPerModule * numberOfModules;
        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), stakingAmount);

        executorInfo[msg.sender] = Executor({
            balance: stakingAmount,
            active: true,
            initialized: true,
            arrayIndex: numberOfActiveExecutors,
            roundsCheckedInEpoch: 0,
            lastCheckinRound: 0,
            lastCheckinEpoch: 0,
            executionsInRoundsInEpoch: 0,
            lastRegistrationTimestamp: block.timestamp,
            registeredModules: validModules
        });
        _activateExecutor(msg.sender);
        emit ModulesRegistered(msg.sender, validModules);
        emit ExecutorActivated(msg.sender);
    }

    /**
     * @notice Unstakes all tokens and deactivates the executor
     * @dev Removes executor from activeExecutors, deletes executor info, and transfers all staking balance back.
     *      Cannot be called during commit phase, execution rounds, or slashing window.
     *      Executor must have waited minimumRegistrationPeriod since last registration.
     * @custom:emits ModulesDeregistered event with executor address and deregistered modules bitset
     * @custom:emits ExecutorDeactivated event if executor was active
     */
    function unstake() public override {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration && block.timestamp < epochEndTime) {
            revert InvalidBlockTime();
        }
        Executor memory executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotActiveExecutor();
        unchecked {
            // should never overflow uint256 in practise, lastRegistrationTimestamp can only be set to block.timestamp
            if (block.timestamp < executor.lastRegistrationTimestamp + minimumRegistrationPeriod) {
                revert MinimumRegistrationPeriodNotOver();
            }
        }

        // *** DELETION, DEACTIVATION AND TRANSFER ***
        delete executorInfo[msg.sender];
        delete commitmentMap[msg.sender];
        if (executor.active) {
            (address deactivatedExecutor, address lastExecutor) = _deactivateExecutor(executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = executor.arrayIndex;
            emit ExecutorDeactivated(deactivatedExecutor);
        }
        ERC20(stakingToken).safeTransfer(msg.sender, executor.balance);
        emit ModulesDeregistered(msg.sender, executor.registeredModules);
    }

    /**
     * @notice Increases the executor's staking balance by the specified amount
     * @dev If the new balance is above threshold and executor was inactive, executor is reactivated.
     *      Cannot be called during execution rounds or slashing window.
     * @param _amount Amount of staking tokens to add to executor's balance
     * @custom:emits ExecutorActivated event if executor is reactivated due to topup
     */
    function topup(uint256 _amount) public override {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration && block.timestamp < epochEndTime)
        {
            revert InvalidBlockTime();
        }
        Executor storage executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotInitializedExecutor();
        uint256 numberOfModules = _countModules(executor.registeredModules);
        if (executor.balance + _amount < stakingAmountPerModule * numberOfModules) revert FinalBalanceBelowMinimum();

        // *** TRANSFER ***
        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        unchecked {
            // sum of all user balances will never exceed uint256 max value
            executor.balance += _amount;
        }
        // *** POTENTIAL ACTIVATION ***
        if (!executor.active) {
            // activate executor if executor was inactive. Have already checked that balance is enough to activate
            executor.active = true;
            _activateExecutor(msg.sender);
            emit ExecutorActivated(msg.sender);
        }
    }

    /**
     * @notice Slashes an executor for not executing in their designated round
     * @dev Can only be called during slashing window. Verifies executor was selected for the round and didn't execute.
     *      Half of slashed amount goes to recipient, other half to protocol balance.
     * @param _executor Address of the executor to slash
     * @param _round Round number the executor failed to execute in
     * @param _recipient Address to receive half of the slashed amount as reward
     * @custom:emits InactiveExecutorSlashed event with executor, recipient, epoch, round, and slash amount
     * @custom:emits ExecutorDeactivated event if executor balance falls below threshold after slashing
     */
    function slashInactiveExecutor(address _executor, uint8 _round, address _recipient) public override {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime || block.timestamp < epochEndTime - slashingDuration) {
            revert InvalidBlockTime();
        }
        if (_round >= roundsPerEpoch) revert RoundExceedingTotal();
        if (numberOfActiveExecutors == 0) revert NoActiveExecutors();
        uint192 currentEpoch = epoch;
        // check if the executor did execute this epoch
        Executor storage executor = executorInfo[_executor];
        // dont have to check if executor is active becasue we verify that executor.arayIndex is selected
        uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, _round))) % uint256(numberOfActiveExecutors);
        if (executor.arrayIndex != executorIndex) revert ExecutorNotSelectedForRound();
        if (executor.lastCheckinEpoch == currentEpoch && executor.lastCheckinRound == _round) revert RoundExecuted();

        // *** LAST CHECKIN UPDATE ***
        // prevent from slashing again - set lastCheckinEpoch to currentEpoch and lastCheckinRound to _round in one storage write (they reside in same slot)
        assembly {
            let slot := executorInfo.slot
            mstore(0x00, _executor)
            mstore(0x20, slot)
            let executorSlot := keccak256(0x00, 0x40)
            let currentValue := sload(add(executorSlot, 1))
            // make 25 bytes of checking round and epoch
            let checkinVals := shl(0, _round)
            checkinVals := or(checkinVals, shl(8, currentEpoch))
            // and(currentValue, 0xFFFFFFFFFFFFFF) keeps the first 7 bytes
            let finalVal := or(and(currentValue, 0xFFFFFFFFFFFFFF), shl(56, checkinVals))
            sstore(add(executorSlot, 1), finalVal)
        }

        // *** SLASHING ***
        uint256 slashAmount = inactiveSlashingAmountPerModule * _countModules(executor.registeredModules);
        _slash(slashAmount, executor, _recipient);

        emit InactiveExecutorSlashed(_executor, _recipient, currentEpoch, _round, slashAmount);
    }

    /**
     * @notice Slashes an executor for committing without revealing their signature
     * @dev Can only be called during slashing window. Verifies executor committed but didn't reveal in the current epoch.
     *      Half of slashed amount goes to recipient, other half to protocol balance.
     * @param _executor Address of the executor to slash
     * @param _recipient Address to receive half of the slashed amount as reward
     * @custom:emits CommitterSlashed event with executor, recipient, epoch, and slash amount
     * @custom:emits ExecutorDeactivated event if executor balance falls below threshold after slashing
     */
    function slashCommitter(address _executor, address _recipient) public override {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime || block.timestamp < epochEndTime - slashingDuration) {
            revert InvalidBlockTime();
        }
        uint192 currentEpoch = epoch;
        CommitData storage commitData = commitmentMap[_executor];
        if (commitData.epoch != currentEpoch) revert OldEpoch();
        if (commitData.revealed) revert CommitmentRevealed();

        // *** SLASHING ***
        Executor storage executor = executorInfo[_executor];
        uint256 slashAmount = commitSlashingAmountPerModule * _countModules(executor.registeredModules);
        _slash(slashAmount, executor, _recipient);

        // *** PREVENT FROM SLASHING AGAIN ***
        commitData.revealed = true;

        emit CommitterSlashed(_executor, _recipient, currentEpoch, slashAmount);
    }

    /**
     * @notice Initiates a new epoch, distributing rewards and resetting state
     * @dev Calculates protocol cut, distributes pool rewards to designated executors, and updates epoch state.
     *      Can be called by anyone once the current epoch has ended. Resets poolCutReceivers array.
     * @custom:emits EpochInitiated event with new epoch number, total distributed rewards, and protocol cut
     */
    function initiateEpoch() public override {
        // *** CHECKS ***
        if (block.timestamp < epochEndTime) revert InvalidBlockTime();

        // *** POOL CUT CALCULATION ***
        uint256 remainingPoolBalance = epochPoolBalance;
        uint256 protocolCut = (remainingPoolBalance * protocolPoolCutBps) / BPS_DENOMINATOR;
        protocolBalance += protocolCut;
        remainingPoolBalance -= protocolCut;

        // *** REWARD DISTRIBUTION ***
        uint256 totalDistributed;
        // distribute pool balance to designated excutors of epoch who executed jobs which were created before epoch started
        if (executedJobsInRoundsOfEpoch > 0) {
            uint256 maxRewardTokensPerRound = remainingPoolBalance / roundsPerEpoch;
            uint256 numberOfReceivers = poolCutReceivers.length;

            for (uint256 i; i < numberOfReceivers;) {
                unchecked {
                    // Safe because:
                    // 1. executor.roundsCheckedInEpoch * maxRewardTokensPerRound cannot overflow (not enough tokens exist)
                    // 2. maxRewardPerExecution * executor.executionsInRoundsInEpoch cannot overflow (not enough tokens exist)
                    // 3. executor.balance += executorShare cannot overflow (not enough tokens exist)
                    // 4. totalDistributed += executorShare cannot overflow (not enough tokens exist)
                    // 5. ++i is safe because numberOfReceivers is less than uint256 max value

                    // if executor has unstaked in the mean time, executor.executionsInEpochCreatedBeforeEpoch and the cut amount will be 0
                    Executor storage executor = executorInfo[poolCutReceivers[i]];
                    // max number of tokens that can be rewarded to executor for this epoch, it is scaled by number of checked in rounds
                    uint256 maxRewardTokens = executor.roundsCheckedInEpoch * maxRewardTokensPerRound;
                    uint256 executionRewards = maxRewardPerExecution * executor.executionsInRoundsInEpoch;

                    // take min of executionRewards and maxRewardTokens
                    uint256 executorShare = executionRewards < maxRewardTokens ? executionRewards : maxRewardTokens;

                    if (executorShare > 0) {
                        // skip if executorShare is 0
                        executor.balance += executorShare;
                        totalDistributed += executorShare;
                    }
                    // these are in same slot, update via assembly
                    executor.roundsCheckedInEpoch = 0;
                    executor.executionsInRoundsInEpoch = 0;
                    ++i;
                }
            }
            delete poolCutReceivers;
            executedJobsInRoundsOfEpoch = 0;
        }

        // *** EPOCH UPDATES ***
        unchecked {
            // pool balances will never overflow uint256 in practise (not enough tokens in existence)
            // epochPoolBalance >= (totalDistributed + protocolCut) should always hold true
            epochPoolBalance += nextEpochPoolBalance - (totalDistributed + protocolCut);
        }
        nextEpochPoolBalance = 0;
        uint192 newEpoch;
        unchecked {
            // block.timestamp + uint8 will not reach uint256 in practise
            // number of epochs will not exceed uint192 in practise
            epochEndTime = block.timestamp + epochDuration;
            newEpoch = ++epoch;
        }

        seed = keccak256(abi.encodePacked(newEpoch));
        emit EpochInitiated(newEpoch, totalDistributed, protocolCut);
    }

    /**
     * @notice Commits a hash of the executor's signature for the commit-reveal scheme
     * @dev Can only be called during commit phase by active executors. The commitment should be keccak256(signature)
     *      where signature is an ERC-191 signature of (epoch, chainid).
     * @param _commitment Hash of the executor's ERC-191 signature of the current epoch
     * @custom:emits Commitment event with executor address and epoch number
     */
    function commit(bytes32 _commitment) public override {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration) {
            revert InvalidBlockTime();
        }
        if (!executorInfo[msg.sender].active) revert NotActiveExecutor();

        // *** COMMITMENT STORAGE ***
        commitmentMap[msg.sender] = CommitData({commitment: _commitment, epoch: epoch, revealed: false});

        emit Commitment(msg.sender, epoch);
    }

    /**
     * @notice Reveals the executor's signature and updates the seed for randomness
     * @dev Can only be called during reveal phase. Verifies signature matches commitment and updates seed.
     *      The seed is used to select designated executors for each round.
     * @param _signature ERC-191 signature of (epoch, chainid) that matches the committed hash
     * @custom:emits Reveal event with executor address, epoch, and new seed
     */
    function reveal(bytes calldata _signature) public override {
        // *** CHECKS ***
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                || block.timestamp < epochEndTime - epochDuration + commitPhaseDuration
        ) {
            revert InvalidBlockTime();
        }

        if (!_verifySignature(epoch, block.chainid, _signature, msg.sender)) revert InvalidSignature();

        CommitData storage commitData = commitmentMap[msg.sender];
        if (commitData.commitment != keccak256(abi.encodePacked(_signature))) revert WrongCommitment();
        if (commitData.revealed) revert CommitmentRevealed();
        if (commitData.epoch != epoch) revert OldEpoch();

        // *** REVEAL ***
        commitData.revealed = true;
        seed = keccak256(abi.encodePacked(seed, _signature));

        emit Reveal(msg.sender, epoch, seed);
    }

    /**
     * @notice Adds a new job registry to the coordinator
     * @dev Can only be called by the owner. Adds registry to jobRegistries array and marks it as valid.
     * @param _registry Address of the job registry contract to add
     */
    function addJobRegistry(address _registry) public override onlyOwner {
        jobRegistries.push(_registry);
        isJobRegistry[_registry] = true;
    }

    /**
     * @notice Registers the executor for additional modules
     * @dev Executor must already be initialized. Transfers additional staking tokens for new modules.
     *      Bitset should only contain bits for new modules, not already registered ones.
     * @param _modulesBitset Bitset representing new modules to register for
     * @return stakingAmount Total amount of additional staking tokens transferred
     * @custom:emits ModulesRegistered event with executor address and updated modules bitset
     */
    function registerModules(uint256 _modulesBitset) public override returns (uint256 stakingAmount) {
        // *** CHECKS ***
        Executor storage executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotInitializedExecutor();
        if (_hasCommonModules(executor.registeredModules, _modulesBitset)) revert SomeModulesAlreadyRegistered();

        // only allow registration for existing modules
        uint256 validModules = _modulesBitset & _getValidModulesMask();

        // *** TRANSFER STAKE ***
        // executor has to stake for each registered module
        // if the executor balance is already below thereshold, this will not be enough to activate it
        uint256 numberOfNewModules = _countModules(validModules);
        if (numberOfNewModules > 0) {
            ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), numberOfNewModules * stakingAmountPerModule);
        } else {
            revert NoModulesToRegister();
        }
        unchecked {
            // sum of all user balances will never exceed uint256 max value
            stakingAmount = numberOfNewModules * stakingAmountPerModule;
            executor.balance += stakingAmount;
        }
        executor.lastRegistrationTimestamp = block.timestamp;

        // *** MODULE REGISTRATION ***
        _registerModule(executor, validModules);

        emit ModulesRegistered(msg.sender, executor.registeredModules);
    }

    /**
     * @notice Deregisters the executor from specified modules
     * @dev Executor must wait minimumRegistrationPeriod since last registration/module addition.
     *      Executor must maintain at least 2 registered modules after deregistration.
     * @param _modulesBitset Bitset representing modules to deregister from
     * @custom:emits ModulesDeregistered event with executor address and updated modules bitset
     */
    function deregisterModules(uint256 _modulesBitset) public override {
        // *** CHECKS ***
        Executor storage executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotInitializedExecutor();
        unchecked {
            // should never overflow uint256 in practise, lastRegistrationTimestamp can only be set to block.timestamp
            if (block.timestamp < executor.lastRegistrationTimestamp + minimumRegistrationPeriod) {
                revert MinimumRegistrationPeriodNotOver();
            }
        }

        // *** DEREGISTRATION ***
        _deregisterModule(executor, _modulesBitset);
        if (_countModules(executor.registeredModules) < 2) revert NumberOfRegisteredModulesBelowMinimum();

        emit ModulesDeregistered(msg.sender, executor.registeredModules);
    }

    /**
     * @notice Withdraws a portion of the executor's staking balance
     * @dev Executor balance after withdrawal must remain above stakingAmountPerModule * number of modules.
     *      Transfers staking tokens from contract to executor.
     * @param _amount Amount of staking tokens to withdraw
     */
    function withdrawStakingBalance(uint256 _amount) public override {
        // executor balance has to be above threshold
        Executor storage executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotInitializedExecutor();

        uint256 numberOfModules = _countModules(executor.registeredModules);
        if (executor.balance - _amount < stakingAmountPerModule * numberOfModules) revert FinalBalanceBelowMinimum();

        executor.balance -= _amount;
        ERC20(stakingToken).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Withdraws the protocol balance to the specified recipient
     * @dev Can only be called by the owner. Transfers all protocol balance and resets it to zero.
     * @param _recipient Address to receive the protocol balance
     * @return amount Amount of protocol balance withdrawn
     */
    function withdrawProtocolBalance(address _recipient) public override onlyOwner returns (uint256 amount) {
        amount = protocolBalance;
        protocolBalance = 0;
        ERC20(stakingToken).safeTransfer(_recipient, amount);
    }

    /**
     * @notice Registers the executor for specific modules
     * @dev Internal function that updates the executor's registeredModules bitset
     * @param executor Storage reference to the executor
     * @param _modulesBitset Bitset representing modules to register for
     */
    function _registerModule(Executor storage executor, uint256 _modulesBitset) private {
        executor.registeredModules |= _modulesBitset;
    }

    /**
     * @notice Deregisters the executor from specific modules
     * @dev Internal function that updates the executor's registeredModules bitset
     * @param executor Storage reference to the executor
     * @param _modulesBitset Bitset representing modules to deregister from
     */
    function _deregisterModule(Executor storage executor, uint256 _modulesBitset) private {
        executor.registeredModules &= ~_modulesBitset;
    }

    /**
     * @notice Counts the number of modules in a bitset (number of set bits)
     * @dev Uses bit manipulation for efficient counting
     * @param _modulesBitset The bitset to count modules in
     * @return count Number of modules (set bits) in the bitset
     */
    function _countModules(uint256 _modulesBitset) private pure returns (uint256) {
        uint256 x = _modulesBitset;
        x = x - ((x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555);
        x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333)
            + ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);
        x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
        return (x * 0x0101010101010101010101010101010101010101010101010101010101010101) >> 248;
    }

    /**
     * @notice Checks if two module bitsets have any modules in common
     * @param _modulesA First module bitset
     * @param _modulesB Second module bitset
     * @return true if the bitsets share at least one active module
     */
    function _hasCommonModules(uint256 _modulesA, uint256 _modulesB) private pure returns (bool) {
        return (_modulesA & _modulesB) != 0;
    }

    /**
     * @notice Creates a mask for valid modules based on current module count
     * @dev Returns a bitset with 1s for all valid module positions (e.g., if 4 modules exist, returns ...0001111)
     * @return mask Bitset mask with 1s for all valid module positions
     */
    function _getValidModulesMask() private view returns (uint256) {
        // e.g. if currentModuleCount = 4, mask = ...0000000000011111
        return (1 << modules.length) - 1;
    }

    /**
     * @notice Activates the executor, adding it to activeExecutors array
     * @dev Reuses empty slots in array if available, otherwise pushes to end. Increments numberOfActiveExecutors.
     *      Should only be called together with setting executor.active to true.
     * @param _executor Address of the executor to activate
     */
    function _activateExecutor(address _executor) private {
        if (numberOfActiveExecutors < activeExecutors.length) {
            // find the first empty slot and insert
            activeExecutors[numberOfActiveExecutors] = _executor;
        } else {
            // push at the end of the array
            activeExecutors.push(_executor);
        }
        unchecked {
            // number of active executors will never be more than uint32 max value in practise
            ++numberOfActiveExecutors;
        }
    }

    /**
     * @notice Deactivates the executor, removing it from activeExecutors array
     * @dev Swaps executor with last element and decrements numberOfActiveExecutors. Maintains array invariant.
     *      Should only be called when executor is active.
     * @param _index Index of the executor in activeExecutors array
     * @return executorAtIndex Address of the executor that was at the given index
     * @return lastExecutor Address of the executor that was moved to fill the gap
     */
    function _deactivateExecutor(uint32 _index) private returns (address, address) {
        uint32 newNumberOfActiveExecutors;
        unchecked {
            // here the executor is active, so numberOfActiveExecutors should be greater than 0
            newNumberOfActiveExecutors = --numberOfActiveExecutors;
        }
        address lastExecutor = activeExecutors[newNumberOfActiveExecutors];
        address deactivatedExecutor = activeExecutors[_index];
        activeExecutors[_index] = lastExecutor;
        delete activeExecutors[newNumberOfActiveExecutors];
        return (deactivatedExecutor, lastExecutor);
    }

    /**
     * @notice Slashes the executor and distributes the slashed amount
     * @dev Deducts amount from executor balance. Half goes to recipient (internal balance if executor, otherwise transfer),
     *      other half to protocol balance. Deactivates executor if balance falls below threshold.
     * @param _amount Amount to slash from executor's balance
     * @param _executor Storage reference to the executor being slashed
     * @param _recipient Address to receive half of the slashed amount
     * @custom:emits ExecutorDeactivated event if executor is deactivated due to low balance
     */
    function _slash(uint256 _amount, Executor storage _executor, address _recipient) private {
        // *** BALANCE THRESHOLD CHECK AND POTENTIAL DEACTIVATION ***
        if (
            (_executor.balance -= _amount)
                < stakingBalanceThresholdPerModule * _countModules(_executor.registeredModules)
        ) {
            // index in activeStakers array
            (address deactivatedExecutor, address lastExecutor) = _deactivateExecutor(_executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = _executor.arrayIndex;
            _executor.active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }
        // *** SLASH REWARD TRANSFER ***
        unchecked {
            // no division by zero. Total token balances will not exceed uint256 max value
            uint256 rewardAmount = _amount / 2;
            if (executorInfo[_recipient].initialized) {
                executorInfo[_recipient].balance += rewardAmount;
            } else {
                // if recipient is not an initialized executor, do normal ERC20 transfer
                ERC20(stakingToken).safeTransfer(_recipient, rewardAmount);
            }
            protocolBalance += _amount - rewardAmount;
        }
    }

    /**
     * @notice Verifies an ERC-191 signature for the given epoch and chainId
     * @dev Uses ecrecover to verify the signature matches the expected signer
     * @param _epochNum Epoch number that was signed
     * @param _chainId Chain ID that was signed
     * @param _signature Signature to verify (65 bytes)
     * @param _expectedSigner Address that should have signed the message
     * @return isValid True if signature is valid and matches expected signer
     */
    function _verifySignature(uint192 _epochNum, uint256 _chainId, bytes memory _signature, address _expectedSigner)
        private
        pure
        returns (bool)
    {
        bytes32 messageHash = keccak256(abi.encodePacked(_epochNum, _chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        return ecrecover(ethSignedMessageHash, v, r, s) == _expectedSigner;
    }

    /**
     * @notice Splits a 65-byte signature into r, s, and v components
     * @param _sig Signature bytes (must be exactly 65 bytes)
     * @return r R component of the signature
     * @return s S component of the signature
     * @return v V component of the signature (27 or 28)
     */
    function _splitSignature(bytes memory _sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (_sig.length != 65) revert InvalidSignatureLength();
        assembly {
            r := mload(add(_sig, 32))
            s := mload(add(_sig, 64))
            v := byte(0, mload(add(_sig, 96)))
        }
    }

    /**
     * @notice Exports the complete configuration of the Coordinator contract
     * @dev Returns encoded configuration data for off-chain tools and verification
     * @return config Encoded bytes containing all configuration parameters
     */
    function exportConfig() public view returns (bytes memory) {
        return abi.encode(
            stakingToken,
            stakingAmountPerModule,
            minimumRegistrationPeriod,
            stakingBalanceThresholdPerModule,
            inactiveSlashingAmountPerModule,
            commitSlashingAmountPerModule,
            roundsPerEpoch,
            roundDuration,
            roundBuffer,
            slashingDuration,
            commitPhaseDuration,
            revealPhaseDuration,
            modules.length,
            executionTax,
            zeroFeeExecutionTax,
            protocolPoolCutBps
        );
    }

    /**
     * @notice Returns the tax configuration of the Coordinator
     * @return stakingToken Address of the ERC20 token used for staking
     * @return executionTax Execution tax amount in staking token units
     * @return protocolPoolCutBps Protocol pool cut in basis points (e.g., 1000 = 10%)
     */
    function getTaxConfig() public view returns (address, uint256, uint256) {
        return (stakingToken, executionTax, protocolPoolCutBps);
    }
}
