// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Coordinator} from "../../src/Coordinator.sol";

/// @author Victor Brevig
contract MockCoordinator is Coordinator {
    constructor(InitSpec memory _spec, address _treasury) Coordinator(_spec, _treasury) {}

    function setSeed(bytes32 _seed) public {
        seed = _seed;
    }

    function setExecutorInfo(Executor memory _executorInfo, address _executor) public {
        executorInfo[_executor] = _executorInfo;
    }

    function getStakingBalanceThresholdPerModule() public view returns (uint256) {
        return stakingBalanceThresholdPerModule;
    }

    function setExecutorBalance(uint256 _balance, address _executor) public {
        executorInfo[_executor].balance = _balance;
    }

    function setLastCheckin(uint8 _lastCheckinRound, uint96 _lastCheckinEpoch, address _executor) public {
        executorInfo[_executor].lastCheckinRound = _lastCheckinRound;
        executorInfo[_executor].lastCheckinEpoch = _lastCheckinEpoch;
    }

    function setLastRegistrationTimestamp(uint256 _lastRegistrationTimestamp, address _executor) public {
        executorInfo[_executor].lastRegistrationTimestamp = _lastRegistrationTimestamp;
    }

    function setPoolCutReceivers(address[] memory _poolCutReceivers) public {
        poolCutReceivers = _poolCutReceivers;
    }

    function setExecutedJobsInRoundsOfEpoch(uint96 _executedJobsInRoundsOfEpoch) public {
        executedJobsInRoundsOfEpoch = _executedJobsInRoundsOfEpoch;
    }

    function setExecutionsInRoundsInEpoch(uint96 _executionsInRoundsInEpoch, address _executor) public {
        executorInfo[_executor].executionsInRoundsInEpoch = _executionsInRoundsInEpoch;
    }

    function getStakingAmountPerModule() public view returns (uint256) {
        return stakingAmountPerModule;
    }

    function setEpochEndTime(uint256 _epochEndTime) public {
        epochEndTime = _epochEndTime;
    }

    function setRoundsCheckedInEpoch(uint8 _roundsCheckedInEpoch, address _executor) public {
        executorInfo[_executor].roundsCheckedInEpoch = _roundsCheckedInEpoch;
    }

    function getEpochPoolBalance() public view returns (uint256) {
        return epochPoolBalance;
    }

    function setEpochPoolBalance(uint256 _epochPoolBalance) public {
        epochPoolBalance = _epochPoolBalance;
    }

    function getNextEpochPoolBalance() public view returns (uint256) {
        return nextEpochPoolBalance;
    }

    function setNextEpochPoolBalance(uint256 _nextEpochPoolBalance) public {
        nextEpochPoolBalance = _nextEpochPoolBalance;
    }

    function getSlashingDuration() public view returns (uint256) {
        return slashingDuration;
    }

    function setCommitment(CommitData memory _commitment, address _executor) public {
        commitmentMap[_executor] = _commitment;
    }

    function setEpoch(uint192 _epoch) public {
        epoch = _epoch;
    }

    function setNumberOfActiveExecutors(uint32 _numberOfActiveExecutors) public {
        numberOfActiveExecutors = _numberOfActiveExecutors;
    }

    function getActiveExecutorsLength() public view returns (uint256) {
        return activeExecutors.length;
    }

    function getEpochDuration() public view returns (uint256) {
        return epochDuration;
    }

    function getSelectionPhaseDuration() public view returns (uint256) {
        return selectionPhaseDuration;
    }

    function getTotalRoundDuration() public view returns (uint256) {
        return totalRoundDuration;
    }

    function getNumberOfActiveExecutors() public view returns (uint40) {
        return numberOfActiveExecutors;
    }

    function getMinimumRegistrationPeriod() public view returns (uint256) {
        return minimumRegistrationPeriod;
    }

    function getCommitPhaseDuration() public view returns (uint256) {
        return commitPhaseDuration;
    }

    function getProtocolBalance() public view returns (uint256) {
        return protocolBalance;
    }

    function getRoundDuration() public view returns (uint256) {
        return roundDuration;
    }

    function getRoundBuffer() public view returns (uint256) {
        return roundBuffer;
    }

    function getRoundsPerEpoch() public view returns (uint8) {
        return roundsPerEpoch;
    }

    function getPoolCutReceiversLength() public view returns (uint256) {
        return poolCutReceivers.length;
    }

    function getExecutedJobsInRoundsOfEpoch() public view returns (uint256) {
        return executedJobsInRoundsOfEpoch;
    }
}
