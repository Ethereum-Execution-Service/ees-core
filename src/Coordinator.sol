// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ICoordinator} from "./interfaces/ICoordinator.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";
import {TaxHandler} from "./TaxHandler.sol";
import {ModuleRegistry} from "./ModuleRegistry.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";


/**
__/\\\\\\\\\\\\\\\__/\\\\\\\\\\\\\\\_____/\\\\\\\\\\\___        
 _\/\\\///////////__\/\\\///////////____/\\\/////////\\\_       
  _\/\\\_____________\/\\\______________\//\\\______\///__      
   _\/\\\\\\\\\\\_____\/\\\\\\\\\\\_______\////\\\_________     
    _\/\\\///////______\/\\\///////___________\////\\\______    
     _\/\\\_____________\/\\\_____________________\////\\\___   
      _\/\\\_____________\/\\\______________/\\\______\//\\\__  
       _\/\\\\\\\\\\\\\\\_\/\\\\\\\\\\\\\\\_\///\\\\\\\\\\\/___ 
        _\///////////////__\///////////////____\///////////_____
 */

/// @author Victor Brevig
/// @notice Coordinator is responsible for coordination of executors including job execution, staking and slashing.
contract Coordinator is ICoordinator, TaxHandler, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    address[] public jobRegistries;
    mapping(address => bool) public isJobRegistry;
    
    bytes32 public seed;
    uint192 public epoch;
    uint256 public epochEndTime;
    uint32 public numberOfActiveExecutors;

    address internal immutable stakingToken;
    uint256 internal immutable stakingAmountPerModule;
    uint256 internal immutable minimumRegistrationPeriod;
    // minimum amount of staking balance required to be eligible to execute
    uint256 internal immutable stakingBalanceThresholdPerModule;
    // amount to slash from the executor upon inactivity.
    uint256 internal immutable inactiveSlashingAmountPerModule;

    // amount to slash for committing without revealing
    uint256 internal immutable commitSlashingAmountPerModule;

    uint8 internal immutable roundsPerEpoch;

    uint256 public epochPoolBalance;
    uint256 public nextEpochPoolBalance;

    uint256 public protocolBalance;

    // all in seconds
    uint8 internal immutable roundDuration;
    uint8 internal immutable roundBuffer;
    uint8 internal immutable epochDuration;
    uint8 internal immutable commitPhaseDuration;
    uint8 internal immutable revealPhaseDuration;
    uint8 internal immutable selectionPhaseDuration;
    uint8 internal immutable totalRoundDuration;
    // slashing phase
    uint8 internal immutable slashingDuration;

    // addresses of all active executors
    address[] public activeExecutors;
    // executor info
    mapping(address => Executor) public executorInfo;

    // total number of executed jobs (non-including zero-fee jobs) during rounds in this epoch
    uint96 public executedJobsInRoundsOfEpoch;
    // addresses to receive pool cut. These are designated executors who executed at least one job during a round in an epoch. This will reset every epoch.
    address[] public poolCutReceivers;

    mapping(address => CommitData) public commitmentMap;

    constructor(InitSpec memory _spec, address _treasury) TaxHandler(_treasury, _spec.executionTax, _spec.zeroFeeExecutionTax, _spec.protocolPoolCutBps) {
        require(
            _spec.stakingBalanceThresholdPerModule <= _spec.stakingAmountPerModule,
            "Staking: threshold must be less than or equal to staking amount"
        );
        require(
            uint256(_spec.roundsPerEpoch) * uint256(_spec.roundDuration + _spec.roundBuffer) <= type(uint8).max * uint256(_spec.roundDuration + _spec.roundBuffer),
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
        epochDuration = selectionPhaseDuration + totalRoundDuration * roundsPerEpoch + slashingDuration;
        commitPhaseDuration = _spec.commitPhaseDuration;
        revealPhaseDuration = _spec.revealPhaseDuration;
        epochEndTime = block.timestamp;
    }

    /**
     * @notice Executes the jobs with the given indices.
     * @notice Outside rounds the executor pays the protocol tax and the executor tax.
     * @notice If the current block.timestamp is in a round, only the selected executor can call and pays no executor tax.
     * @notice If executor checks in, the executor will be rewarded with the pool cut.
     * @notice This function does not revert if any of the calls to execute jobs reverts.
     * @param _indices The indices of the jobs to execute.
     * @param _feeRecipient The address to receive excution fees.
     */
    function executeBatch(
        uint256[] calldata _indices,
        uint256[] calldata _gasLimits,
        address _feeRecipient,
        uint8 _jobRegistryIndex
    ) public nonReentrant returns (uint256, uint256, uint96) {
        Executor memory executor = executorInfo[msg.sender];

        // *** IN ROUND CHECKS ***
        bool inRound;
        uint8 round;
        uint256 designatedExecutorModules;
        address designatedExecutor;
        if (block.timestamp < epochEndTime - slashingDuration && block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration)
        {
            // in alternating open competition and designated rounds part of the epoch
            uint256 timeIntoRounds;
            unchecked {
                // safe given that 1) epochEndTime > block.timestamp and 2) block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                timeIntoRounds = epochDuration - selectionPhaseDuration - (epochEndTime - block.timestamp);
                // totalRoundDuration is > 0 becasue of constructor check on totalRoundDuration
                inRound = timeIntoRounds % totalRoundDuration < roundDuration;
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
        uint8 epochDurationCache = epochDuration;
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
            mstore(0x40, add(returnDataPtr, 0xA0))  // advance by 160 bytes (5 * 32)
            
            let epochStartTime := sub(sload(epochEndTime.slot), epochDurationCache)

            for {} lt(i, indicesLength) {} {
                let index := calldataload(add(_indices.offset, mul(i, 0x20)))
                let gasLimit := calldataload(add(_gasLimits.offset, mul(i, 0x20)))

                mstore(add(inputPtr, 0x04), index)
                mstore(add(inputPtr, 0x24), _feeRecipient)

                let success := call(
                    gasLimit,        // gas
                    jobRegistryCache,// address
                    0,              // value
                    inputPtr,       // input memory
                    0x44,           // input size
                    returnDataPtr,  // output memory
                    0xC0            // output size (6 * 32 bytes)
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
                        let executionModuleId := and(mload(add(returnDataPtr, 0x40)), 0xFF)  // 3th word
                        let feeModuleId := and(mload(add(returnDataPtr, 0x60)), 0xFF)        // 4th word
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
                if(inRound) {
                    executedJobsInRoundsOfEpoch += executionCount;
                    protocolBalance += standardTax;
                }
                else {
                    nextEpochPoolBalance += standardTax;
                }
            }
        }
        if(executionCountZeroFee > 0) {
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
        if(totalTax > 0) {
            if(executor.initialized) {
                // if executor is initialized, use internal balance
                newBalance = (executorInfo[msg.sender].balance -= totalTax);
            }
            else {
                ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), totalTax);
            }
        }
        // *** DESIGNATED EXECUTOR UPDATES ***
        if (inRound && designatedExecutor == msg.sender) {
            if(!executor.active) revert NotActiveExecutor();

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
                    let packedValue := or(
                        preservedBits,
                        or(
                            shl(48, newRoundsChecked),
                            or(
                                shl(56, round),
                                or(
                                    shl(64, epochValue),
                                    shl(160, newExecutions)
                                )
                            )
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
        if(executor.active && newBalance < stakingBalanceThresholdPerModule * _countModules(executor.registeredModules)) {
            (address deactivatedExecutor, address lastExecutor) = _deactivateExecutor(executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = executor.arrayIndex;
            executorInfo[msg.sender].active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }


        emit BatchExecution(_jobRegistryIndex, standardTax, zeroFeeTax, inRound);
        return (standardTax, zeroFeeTax, executionCount + executionCountZeroFee);
    }

    /**
     * @notice Stakes the stakingToken transfering the stakingAmount to the contract and activates the executor to be able to execute jobs.
     * @notice Caller must not be an already initialized executor. To increase balance use topup instead.
     * @notice Cannot be called during execution rounds and slashing window.
     * @dev Activates the executor, adding it to executorInfo and increments numberOfActiveExecutors.
     * @param _modulesBitset The bitset of modules to register for.
     */
    function stake(uint256 _modulesBitset) public returns (uint256 stakingAmount) {
        // *** CHECKS ***
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime
        ) {
            revert InvalidBlockTime();
        }
        if (executorInfo[msg.sender].initialized) revert AlreadyStaked();

        // *** MODULE REGISTRATION CHECK ***
        // only allow registration for existing modules
        uint256 validModules = _modulesBitset & _getValidModulesMask();
        uint256 numberOfModules = _countModules(validModules);
        if(numberOfModules < 2) revert NumberOfRegisteredModulesBelowMinimum();
        
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
        emit ExecutorActivated(msg.sender);
    }

    /**
     * @notice Unstakes the stakingToken and transfers the balance from the contract to the executor and deactivates the executor.
     * @notice Cannot be called during reveal phase, execution rounds and slashing duration.
     * @dev If the executor is active it is deactivated removing it from activeExecutors and numberOfActiveExecutors is decremented. The executor is removed from executorInfo.
     */
    function unstake() public {
        // *** CHECKS ***
        if (
            block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration
                && block.timestamp < epochEndTime
        ) {
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
    }

    /**
     * @notice Increases the staking balance of the executor by the given amount and activates the executor if end balance is above threshold.
     * @notice Cannot be called during execution rounds and slashing window.
     * @param _amount The amount to topup the staking balance with stakingToken.
     */
    function topup(uint256 _amount) public {
        // *** CHECKS ***
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime
        ) {
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
        if (!executor.active && executor.balance >= stakingAmountPerModule * numberOfModules) {
            executor.active = true;
            _activateExecutor(msg.sender);
            emit ExecutorActivated(msg.sender);
        }
    }

    /**
     * @notice Slashes the executor for not executing in the given round with inactiveSlashingAmountPerModule times the number of registered modules.
     * @notice If executor's balance goes below threshold, executor is deactivated.
     * @notice Cannot only be called during slashing window.
     * @notice If the recipiant is an initialized executor, reward will go to internal balance, otherwise normal ERC20 transfer.
     * @param _executor The address of the executor to be slashed.
     * @param _round The round the executor is being slashed for.
     * @param _recipient The address to send slashing reward to.
     */
    function slashInactiveExecutor(address _executor, uint8 _round, address _recipient) public {
        // *** CHECKS ***
        if (block.timestamp >= epochEndTime || block.timestamp < epochEndTime - slashingDuration) {
            revert InvalidBlockTime();
        }
        if (_round >= roundsPerEpoch) revert RoundExceedingTotal();
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

        emit SlashInactiveExecutor(_executor, _recipient, currentEpoch, _round, slashAmount);
    }

    /**
     * @notice Slashes the executor for committing without revealing with commitSlashingAmountPerModule times the number of registered modules.
     * @notice If executor's balance goes below threshold, executor is deactivated.
     * @notice Cannot only be called during slashing window.
     * @notice If the recipiant is an initialized executor, reward will go to internal balance, otherwise normal ERC20 transfer.
     * @param _executor The address of the executor to be slashed.
     * @param _recipient The address to send slashing reward to.
     */
    function slashCommitter(address _executor, address _recipient) public {
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

        emit SlashCommitter(_executor, _recipient, currentEpoch, slashAmount);
    }

    /**
     * @notice Initiates a new epoch by setting the epochEndTime to the current block.timestamp + epochDuration.
     * @notice Cannot be called before last epoch is done.
     */
    function initiateEpoch() public {
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
        if(executedJobsInRoundsOfEpoch > 0) {
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
                    uint256 executorShare = executionRewards < maxRewardTokens ? 
                        executionRewards : 
                        maxRewardTokens;

                    if(executorShare > 0) {
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
     * @notice Commits a hash of the executor's siganture of the current epoch.
     * @notice Can only be called during commit phase.
     * @param _commitment The commitment to be stored for the executor.
     */
    function commit(bytes32 _commitment) public {
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
     * @notice Reveals the executors signature of the current epoch.
     * @notice Can only be called during reveal phase.
     * @notice Caller must have committed in the same epoch.
     * @param _signature The signature to be verified and used to update the seed.
     */
    function reveal(bytes calldata _signature) public {
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
     * @notice Adds a job registry to the coordinator.
     * @notice Can only be called by the owner.
     * @param _registry The address of the job registry to add.
     */
    function addJobRegistry(address _registry) public onlyOwner {
        jobRegistries.push(_registry);
        isJobRegistry[_registry] = true;
    }


    /**
    * @notice Registers the executor for specific modules
    * @notice The _modulesBitset should only contain bits for new modules to register. Otherwise the call will revert.
    * @param _modulesBitset Bitset representing all modules to register for
    */
    function registerModules(uint256 _modulesBitset) external {
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
        }
        else {
            revert NoModulesToRegister();
        }
        unchecked {
            // sum of all user balances will never exceed uint256 max value
            executor.balance += numberOfNewModules * stakingAmountPerModule;
        }
        executor.lastRegistrationTimestamp = block.timestamp;

        // *** MODULE REGISTRATION ***
        _registerModule(executor, validModules);
        
        emit ModulesRegistered(msg.sender, executor.registeredModules);
    }

    /**
    * @notice Deregisters the executor from specific modules
    * @notice The executor has to wait for the minimum registration period to be over before deregistering modules
    * @param _modulesBitset Bitset representing all modules to deregister from
    */
    function deregisterModules(uint256 _modulesBitset) external {
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
        if(_countModules(executor.registeredModules) < 2) revert NumberOfRegisteredModulesBelowMinimum();
        
        emit ModulesDeregistered(msg.sender, executor.registeredModules);
    }

    /**
     * @notice Withdraws the protocol balance to the owner.
     * @notice Can only be called by the owner.
     * @return amount The amount of protocol balance withdrawn.
     */
    function withdrawProtocolBalance() public onlyOwner returns (uint256) {
        uint256 amount = protocolBalance;
        protocolBalance = 0;
        ERC20(stakingToken).safeTransfer(owner, amount);
        return amount;
    }

    /**
     * @notice Registers the executor for specific modules
     * @param _modulesBitset Bitset representing all modules to register for
     */
    function _registerModule(Executor storage executor, uint256 _modulesBitset) private {
        executor.registeredModules |= _modulesBitset;
    }

    /**
     * @notice Deregisters the executor from specific modules
     * @param _modulesBitset Bitset representing all modules to deregister from
     */
    function _deregisterModule(Executor storage executor, uint256 _modulesBitset) private {
        executor.registeredModules &= ~_modulesBitset;
    }

    /**
    * @notice Counts number of modules registered (number of 1s in bitset)
    * @param _modulesBitset The bitset to count
    * @return count The number of modules registered
    */
    function _countModules(uint256 _modulesBitset) private pure returns (uint256) {
        uint256 x = _modulesBitset;
        x = x - ((x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555);
        x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333) + ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);
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
     * @notice Creates a mask for valid modules based on currentModuleCount
     * @return mask The mask with 1s for all valid module positions
     */
    function _getValidModulesMask() private view returns (uint256) {
        // e.g. if currentModuleCount = 4, mask = ...0000000000011111
        return (1 << modules.length) - 1;
    }

    /**
     * @notice Activates the executor, adding it to activeExecutors and increments numberOfActiveExecutors.
     * @dev Should only be used together with setting executor.active to true.
     * @param _executor The address of the executor to be activated.
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
     * @notice Deactivates the executor, removing it from activeExecutors and decrements numberOfActiveExecutors.
     * @dev Should only be called when the executor is active.
     * @dev Should only be used together with setting executor.active to false or deleting executorInfo entry.
     * @param _index The index of the executor in activeExecutors.
     * @return executorAtIndex The address of the executor at the given index.
     * @return lastExecutor The address of the last executor in activeExecutors.
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
     * @notice Slashes the executor for the given amount and sends half to the recipient.
     * @notice If the recipiant is an initialized executor, reward will go to internal balance, otherwise normal ERC20 transfer.
     * @dev Should only be called when the executor is active.
     * @param _amount The amount to slash from the executor's balance.
     * @param _executor The address of the executor to be slashed.
     * @param _recipient The address to reward half of the slashed amount to.
     */
    function _slash(uint256 _amount, Executor storage _executor, address _recipient) private {
        // *** BALANCE THRESHOLD CHECK AND POTENTIAL DEACTIVATION ***
        if ((_executor.balance -= _amount) < stakingBalanceThresholdPerModule * _countModules(_executor.registeredModules)) {
            // index in activeStakers array
            (address deactivatedExecutor,address lastExecutor) = _deactivateExecutor(_executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = _executor.arrayIndex;
            _executor.active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }
        // *** SLASH REWARD TRANSFER ***
        unchecked {
            // no division by zero. Total token balances will not exceed uint256 max value
            uint256 rewardAmount = _amount / 2;
            if(executorInfo[_recipient].initialized) {
                executorInfo[_recipient].balance += rewardAmount;
            } else {
                // if recipient is not an initialized executor, do normal ERC20 transfer
                ERC20(stakingToken).safeTransfer(_recipient, rewardAmount);
            }
            protocolBalance += _amount - rewardAmount;
        } 
    }

    /**
     * @notice Verifies the signature of the executor for the given epoch and chainId.
     * @param _epochNum The epoch number to verify the signature for.
     * @param _chainId The chainId to verify the signature for.
     * @param _signature The signature to verify.
     * @param _expectedSigner The expected signer of the signature.
     * @return isValid Is true if the signature is valid, false otherwise.
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
     * @notice Splits the signature into r, s and v.
     * @param _sig The signature to split.
     * @return r The r value of the signature.
     * @return s The s value of the signature.
     * @return v The v value of the signature.
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
     * @notice Exports the configuration of the ExecutionManager contract
     * @return config A bytes array containing the encoded configuration data
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
     * @notice Exports the tax configuration of the Coordinator contract
     * @return stakingToken The address of the staking token
     * @return executionTax The execution tax
     * @return protocolPoolCutBps The protocol pool cut in basis points
     */
    function getTaxConfig() public view returns (address, uint256, uint256) {
        return (stakingToken, executionTax, protocolPoolCutBps);
    }
}
