// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IQuerier} from "./interfaces/IQuerier.sol";
import {JobRegistry} from "./JobRegistry.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IApplication} from "./interfaces/IApplication.sol";
import {Coordinator} from "./Coordinator.sol";
import {ICoordinator} from "./interfaces/ICoordinator.sol";

contract Querier is IQuerier {
    JobRegistry jobRegistry;
    Coordinator coordinator;

    constructor(JobRegistry _jobRegistry, Coordinator _coordinator) {
        jobRegistry = _jobRegistry;
        coordinator = _coordinator;
    }

    function getJobs(uint256[] calldata _indices) public view override returns (JobData[] memory) {
        JobData[] memory jobsData = new JobData[](_indices.length);
        for (uint256 i; i < _indices.length;) {
            uint256 index = _indices[i];
            (
                address owner,
                bool active,
                bool ignoreAppRevert,
                uint40 inactiveGracePeriod,
                address sponsor,
                uint48 executionCounter,
                uint48 maxExecutions,
                IApplication application,
                bytes1 executionModule,
                bytes1 feeModule,
                uint32 executionWindow
            ) = jobRegistry.jobs(index);
            IExecutionModule executionModuleContract = jobRegistry.executionModules(uint8(executionModule));
            IFeeModule feeModuleContract = jobRegistry.feeModules(uint8(feeModule));
            JobData memory jobData = JobData({
                index: index,
                owner: owner,
                active: active,
                ignoreAppRevert: ignoreAppRevert,
                inactiveGracePeriod: inactiveGracePeriod,
                sponsor: sponsor,
                application: application,
                executionCounter: executionCounter,
                maxExecutions: maxExecutions,
                executionModule: executionModule,
                feeModule: feeModule,
                executionWindow: executionWindow,
                executionModuleData: executionModuleContract.getEncodedData(index),
                feeModuleData: feeModuleContract.getEncodedData(index),
                jobIsExpired: executionModuleContract.jobIsExpired(index, executionWindow),
                jobInExecutionWindow: executionModuleContract.jobIsInExecutionMode(index, executionWindow)
            });
            jobsData[i] = jobData;
            unchecked {
                ++i;
            }
        }

        return jobsData;
    }

    function getExecutors(address[] calldata _executors)
        public
        view
        override
        returns (ICoordinator.Executor[] memory)
    {
        ICoordinator.Executor[] memory executors = new ICoordinator.Executor[](_executors.length);
        for (uint256 i; i < _executors.length;) {
            (
                uint256 balance,
                bool active,
                bool initialized,
                uint40 arrayIndex,
                uint8 lastCheckinRound,
                uint192 lastCheckinEpoch,
                uint256 stakingTimestamp
            ) = coordinator.executorInfo(_executors[i]);
            ICoordinator.Executor memory executor = ICoordinator.Executor({
                balance: balance,
                active: active,
                initialized: initialized,
                arrayIndex: arrayIndex,
                lastCheckinRound: lastCheckinRound,
                lastCheckinEpoch: lastCheckinEpoch,
                stakingTimestamp: stakingTimestamp
            });
            executors[i] = executor;
            unchecked {
                ++i;
            }
        }
        return executors;
    }

    function getCommitData(address[] calldata _executors)
        public
        view
        override
        returns (ICoordinator.CommitData[] memory)
    {
        ICoordinator.CommitData[] memory commitData = new ICoordinator.CommitData[](_executors.length);
        for (uint256 i; i < _executors.length;) {
            (bytes32 commitment, uint192 epoch, bool revealed) = coordinator.commitmentMap(_executors[i]);
            ICoordinator.CommitData memory data =
                ICoordinator.CommitData({commitment: commitment, epoch: epoch, revealed: revealed});
            commitData[i] = data;
            unchecked {
                ++i;
            }
        }
        return commitData;
    }

    function getCurrentEpochInfo() public view override returns (uint192, uint256, bytes32, uint40, address[] memory) {
        uint192 epoch = coordinator.epoch();
        uint40 numberOfActiveExecutors = coordinator.numberOfActiveExecutors();
        bytes32 seed = coordinator.seed();

        bytes memory config = coordinator.exportConfig();
        // Decode the config to get roundsPerEpoch
        (
            ,
            ,
            ,
            ,
            ,
            , // Skip the first 6 parameters
            uint8 roundsPerEpoch,
            ,
            ,
            ,
            ,
            ,
            , // Skip the remaining parameters
        ) = abi.decode(
            config,
            (
                address,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                uint8,
                uint256,
                uint256,
                uint8,
                uint8,
                uint8,
                uint8,
                uint8
            )
        );
        address[] memory selectedExecutors = new address[](roundsPerEpoch);
        for (uint256 i; i < roundsPerEpoch; i++) {
            uint256 executorIndex = uint256(keccak256(abi.encodePacked(seed, i))) % uint256(numberOfActiveExecutors);
            selectedExecutors[i] = coordinator.activeExecutors(executorIndex);
        }
        return (epoch, coordinator.epochEndTime(), seed, numberOfActiveExecutors, selectedExecutors);
    }
}
