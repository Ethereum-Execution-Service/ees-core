// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ICoordinator} from "./interfaces/ICoordinator.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";
import {TaxHandler} from "./TaxHandler.sol";

/// @author Victor Brevig
/// @notice Coordinator is responsible for coordination of executors including job execution, staking and slashing.
contract Coordinator is ICoordinator, TaxHandler {
    using SafeTransferLib for ERC20;

    address internal jobRegistry;
    bytes32 public seed;
    uint192 public epoch;
    uint256 public epochEndTime;
    uint40 public numberOfActiveExecutors;

    address internal immutable stakingToken;
    uint256 internal immutable stakingAmount;
    uint256 internal immutable minimumStakingPeriod;
    // minimum amount of staking balance required to be eligible to execute
    uint256 internal immutable stakingBalanceThreshold;
    // amount to slash from the executor upon inactivity.
    uint256 internal immutable inactiveSlashingAmount;

    // amount to slash for committing without revealing
    uint256 internal immutable commitSlashingAmount;

    uint8 internal immutable roundsPerEpoch;

    uint256 internal epochPoolBalance;
    uint256 internal nextEpochPoolBalance;

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

    address[] public activeExecutors;
    mapping(address => Executor) public executorInfo;

    mapping(address => CommitData) public commitmentMap;

    constructor(InitSpec memory _spec, address _treasury) TaxHandler(_treasury, _spec.protocolTax, _spec.executorTax) {
        require(
            _spec.stakingBalanceThreshold <= _spec.stakingAmount,
            "Staking: threshold must be less than or equal to staking amount"
        );
        totalRoundDuration = _spec.roundDuration + _spec.roundBuffer;
        require(totalRoundDuration > 0, "Staking: round duration and buffer must be greater than 0");

        stakingToken = _spec.stakingToken;
        stakingAmount = _spec.stakingAmount;
        minimumStakingPeriod = _spec.minimumStakingPeriod;
        stakingBalanceThreshold = _spec.stakingBalanceThreshold;
        inactiveSlashingAmount = _spec.inactiveSlashingAmount;
        commitSlashingAmount = _spec.commitSlashingAmount;
        require(
            inactiveSlashingAmount + commitSlashingAmount <= stakingBalanceThreshold,
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
     * @notice If checkIn is true, the executor will be rewarded with the pool cut.
     * @notice This function does not revert if any of the calls to execute jobs reverts.
     * @param _indices The indices of the jobs to execute.
     * @param _feeRecipient The address to receive excution fees.
     * @param _checkIn If true, the the lastCheckinEpoch is updated such that the executor cannot be slashed for inactivity. The executor will be rewarded with the pool cut. Is only relevant if block.timestamp is within a round where the caller is the selected executor.
     */
    function executeBatch(
        uint256[] calldata _indices,
        uint256[] calldata _gasLimits,
        address _feeRecipient,
        bool _checkIn
    ) public returns (uint256[] memory failedIndices) {
        // check that caller is active executor
        Executor memory executor = executorInfo[msg.sender];
        if (!executor.active) revert NotActiveExecutor();

        bool inRound = false;
        uint8 round;
        if (block.timestamp < epochEndTime - slashingDuration && block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration)
        {
            // we are in an epoch
            uint256 timeIntoRounds;
            unchecked {
                // safe given that 1) epochEndTime > block.timestamp and 2) block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                timeIntoRounds = epochDuration - selectionPhaseDuration - (epochEndTime - block.timestamp);
                // totalRoundDuration is > 0 becasue of constructor check on totalRoundDuration
                // current round within the epoch
                inRound = timeIntoRounds % totalRoundDuration < roundDuration;
            }
            if (_checkIn && !inRound) revert CheckInOutsideRound();

            if (inRound) {
                unchecked {
                    // totalRoundDuration is > 0 because of constructor check on totalRoundDuration
                    // guarantee on no uint8 overflow?
                    round = uint8(timeIntoRounds / totalRoundDuration);
                }

                uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, round))) % numberOfActiveExecutors;
                if (activeExecutors[executorIndex] != msg.sender) revert ExecutorNotSelectedForRound();
            }
        }
        // could put these in assembly in memory, but be careful not to override anything
        address jobRegistryCache = jobRegistry;
        uint256 indicesLength = _indices.length;
        assembly {
            // Get the current free memory pointer
            let inputPtr := mload(0x40)

            // the next 3 slots (0x60 bytes) are reserved for the function selector, index, and gas limit
            // function selector doesnt change, so we can store it in memory once
            mstore(inputPtr, shl(224, 0xc032dc30)) // Function selector for execute(uint256,address)

            // Store the pointer to the start of our data
            failedIndices := add(inputPtr, 0x60)

            // Reserve 32 bytes for length, start writing data after that
            let writePtr := add(failedIndices, 0x20)
            let failedCount := 0
            let i := 0
            for {} lt(i, indicesLength) {} {
                let index := calldataload(add(_indices.offset, mul(i, 0x20)))
                let gasLimit := calldataload(add(_gasLimits.offset, mul(i, 0x20)))

                mstore(add(inputPtr, 0x04), index)
                mstore(add(inputPtr, 0x24), _feeRecipient)

                let success := call(gasLimit, jobRegistryCache, 0, inputPtr, 0x44, 0, 0)

                if iszero(success) {
                    mstore(writePtr, index)
                    writePtr := add(writePtr, 32)
                    failedCount := add(failedCount, 1)
                }
                i := add(i, 1)
            }
            mstore(failedIndices, failedCount)
            mstore(0x40, writePtr)
        }

        uint256 numberOfExecutedJobs;
        unchecked {
            // cannot underflow as failedIndices.length <= indicesLength
            numberOfExecutedJobs = indicesLength - failedIndices.length;
        }

        uint256 newBalance = executor.balance;
        if (inRound) {
            if (_checkIn) {
                // check that this is first time in this epoch and round that caller is checking in
                if (executor.lastCheckinEpoch == epoch && executor.lastCheckinRound == round) revert AlreadyCheckedIn();
                // set lastCheckinEpoch to epoch and lastCheckinRound to round in one storage write (they reside in same slot)
                assembly {
                    let epochValue := sload(epoch.slot)
                    let slot := executorInfo.slot
                    mstore(0x00, caller())
                    mstore(0x20, slot)
                    let executorSlot := keccak256(0x00, 0x40)
                    let currentValue := sload(add(executorSlot, 1))
                    // make 25 bytes of checking round and epoch
                    let checkinVals := shl(0, round)
                    checkinVals := or(checkinVals, shl(8, epochValue))
                    // and(currentValue, 0xFFFFFFFFFFFFFF) keeps the first 7 bytes
                    let finalVal := or(and(currentValue, 0xFFFFFFFFFFFFFF), shl(56, checkinVals))
                    sstore(add(executorSlot, 1), finalVal)
                }

                // calculates fraction of *current* epochPoolBalance.
                uint8 roundDiff;
                unchecked {
                    // round should never be more that roundsPerEpoch
                    roundDiff = roundsPerEpoch - round;
                }
                uint256 poolReward = epochPoolBalance / roundDiff;
                uint256 totalProtocolTax = protocolTax * numberOfExecutedJobs;

                if (poolReward >= totalProtocolTax) {
                    unchecked {
                        // balance will not exceed uint256 max value
                        newBalance = (executorInfo[msg.sender].balance += poolReward - totalProtocolTax);
                    }
                } else {
                    newBalance = (executorInfo[msg.sender].balance -= totalProtocolTax - poolReward);
                }
                unchecked {
                    // should never underflow as epochPoolBalance / roundsPerEpoch <= epochPoolBalance
                    epochPoolBalance -= poolReward;
                }

                emit CheckIn(msg.sender, epoch, round);
            } else {
                // not checking in, pay protocol tax
                if (numberOfExecutedJobs > 0) {
                    newBalance = (executorInfo[msg.sender].balance -= protocolTax * numberOfExecutedJobs);
                }
            }
        } else {
            if (numberOfExecutedJobs > 0) {
                // executor pays protocol and executor tax
                newBalance = (executorInfo[msg.sender].balance -= (protocolTax + executorTax) * numberOfExecutedJobs);
                // update pool balance for next epoch
                unchecked {
                    // nextEpochPoolBalance will never exceed uint256 max value since there are not enough tokens in existence
                    nextEpochPoolBalance += executorTax * numberOfExecutedJobs;
                }
            }
        }

        // check if executor balance is below threshold and deactivate if true
        if (newBalance < stakingBalanceThreshold) {
            (address deactivatedExecutor, address lastExecutor) = _deactivateExecutor(executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = executor.arrayIndex;
            executorInfo[msg.sender].active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }

        emit BatchExecution(failedIndices);
    }

    /**
     * @notice Stakes the stakingToken transfering the stakingAmount to the contract and activates the executor to be able to execute jobs.
     * @notice Caller must not be an already initialized executor. To increase balance use topup instead.
     * @notice Cannot be called during execution rounds and slashing window.
     * @dev Activates the executor, adding it to executorInfo and increments numberOfActiveExecutors.
     */
    function stake() public {
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime
        ) {
            revert InvalidBlockTime();
        }
        if (executorInfo[msg.sender].initialized) revert AlreadyStaked();

        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), stakingAmount);

        executorInfo[msg.sender] = Executor({
            balance: stakingAmount,
            active: true,
            initialized: true,
            arrayIndex: numberOfActiveExecutors,
            lastCheckinRound: 0,
            lastCheckinEpoch: 0,
            stakingTimestamp: block.timestamp
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
        if (
            block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration
                && block.timestamp < epochEndTime
        ) {
            revert InvalidBlockTime();
        }

        Executor memory executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotActiveExecutor();
        unchecked {
            // should never overflow uint256 in practise, stakingTimestamp can only be set to block.timestamp
            if (block.timestamp < executor.stakingTimestamp + minimumStakingPeriod) {
                revert MinimumStakingPeriodNotOver();
            }
        }
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
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime
        ) {
            revert InvalidBlockTime();
        }

        Executor storage executor = executorInfo[msg.sender];
        if (!executor.initialized) revert NotActiveExecutor();
        if (executor.balance + _amount < stakingAmount) revert TopupBelowMinimum();

        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        unchecked {
            // sum of all user balances will never exceed uint256 max value
            executor.balance += _amount;
        }
        if (!executor.active && executor.balance >= stakingAmount) {
            executor.active = true;
            _activateExecutor(msg.sender);
            emit ExecutorActivated(msg.sender);
        }
    }

    /**
     * @notice Slashes the executor for not executing in the given round with inactiveSlashingAmount.
     * @notice If executor's balance goes below threshold, executor is deactivated.
     * @notice Cannot only be called during slashing window.
     * @param _executor The address of the executor to be slashed.
     * @param _round The round the executor is being slashed for.
     * @param _recipient The address to send slashing reward to.
     */
    function slashInactiveExecutor(address _executor, uint8 _round, address _recipient) public {
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
        if (executor.lastCheckinEpoch == currentEpoch) revert RoundExecuted();

        // prevent from slashing again
        executor.lastCheckinEpoch = currentEpoch;

        uint256 slashAmount = inactiveSlashingAmount;
        _slash(slashAmount, executor, _recipient);

        emit SlashInactiveExecutor(_executor, _recipient, currentEpoch, _round, slashAmount);
    }

    /**
     * @notice Slashes the executor for committing without revealing with commitSlashingAmount.
     * @notice If executor's balance goes below threshold, executor is deactivated.
     * @notice Cannot only be called during slashing window.
     * @param _executor The address of the executor to be slashed.
     * @param _recipient The address to send slashing reward to.
     */
    function slashCommitter(address _executor, address _recipient) public {
        if (block.timestamp >= epochEndTime || block.timestamp < epochEndTime - slashingDuration) {
            revert InvalidBlockTime();
        }
        uint192 currentEpoch = epoch;
        CommitData storage commitData = commitmentMap[_executor];
        if (commitData.epoch != currentEpoch) revert OldEpoch();
        if (commitData.revealed) revert CommitmentRevealed();

        uint256 slashAmount = commitSlashingAmount;
        // slash the committer
        Executor storage executor = executorInfo[_executor];
        _slash(slashAmount, executor, _recipient);
        commitData.revealed = true;

        emit SlashCommitter(_executor, _recipient, currentEpoch, slashAmount);
    }

    /**
     * @notice Initiates a new epoch by setting the epochEndTime to the current block.timestamp + epochDuration.
     * @notice Cannot be called before last epoch is done plut slashing duration has passed.
     */
    function initiateEpoch() public {
        if (block.timestamp < epochEndTime) revert InvalidBlockTime();
        unchecked {
            // block.timestamp + uint8 will not reach uint256
            epochEndTime = block.timestamp + epochDuration;
        }

        uint192 newEpoch;

        unchecked {
            // number of epochs should not exceed uint192
            newEpoch = ++epoch;
        }
        
        seed = keccak256(abi.encodePacked(newEpoch));
        unchecked {
            // balances will never overflow uint256
            epochPoolBalance += nextEpochPoolBalance;
        }
        nextEpochPoolBalance = 0;
        emit EpochInitiated(newEpoch);
    }

    /**
     * @notice Commits a hash of the executor's siganture of the current epoch.
     * @notice Can only be called during commit phase.
     * @param _commitment The commitment to be stored for the executor.
     */
    function commit(bytes32 _commitment) public {
        if (block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration) {
            revert InvalidBlockTime();
        }
        if (!executorInfo[msg.sender].active) revert NotActiveExecutor();

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

        commitData.revealed = true;
        seed = keccak256(abi.encodePacked(seed, _signature));

        emit Reveal(msg.sender, epoch, seed);
    }

    function setJobRegistry(address _jobRegistry) public onlyOwner {
        jobRegistry = _jobRegistry;
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
            // number of active executors will never be more than uint40 max value in practise
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
    function _deactivateExecutor(uint40 _index) private returns (address, address) {
        uint40 newNumberOfActiveExecutors;
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
     * @dev Should only be called when the executor is active.
     * @param _amount The amount to slash from the executor's balance.
     * @param _executor The address of the executor to be slashed.
     * @param _recipient The address to reward half of the slashed amount to. Must be an active executor.
     */
    function _slash(uint256 _amount, Executor storage _executor, address _recipient) private {
        if (!executorInfo[_recipient].active) revert NotActiveExecutor();

        if ((_executor.balance -= _amount) < stakingBalanceThreshold) {
            // index in activeStakers array
            (address deactivatedExecutor,address lastExecutor) = _deactivateExecutor(_executor.arrayIndex);
            executorInfo[lastExecutor].arrayIndex = _executor.arrayIndex;
            _executor.active = false;
            emit ExecutorDeactivated(deactivatedExecutor);
        }
        unchecked {
            // no division by zero. Total token balances will not exceed uint256 max value
            executorInfo[_recipient].balance += _amount / 2;
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
            stakingAmount,
            minimumStakingPeriod,
            stakingBalanceThreshold,
            inactiveSlashingAmount,
            commitSlashingAmount,
            roundsPerEpoch,
            executorTax,
            protocolTax,
            roundDuration,
            roundBuffer,
            slashingDuration,
            commitPhaseDuration,
            revealPhaseDuration
        );
    }
}
