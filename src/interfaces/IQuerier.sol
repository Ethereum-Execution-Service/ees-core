// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IApplication} from "./IApplication.sol";
import {ICoordinator} from "./ICoordinator.sol";

interface IQuerier {
    struct JobData {
        uint256 index;
        address owner;
        bool active;
        bool ignoreAppRevert;
        uint40 inactiveGracePeriod;
        address sponsor;
        uint48 executionCounter;
        uint48 maxExecutions;
        IApplication application;
        bytes1 executionModule;
        bytes1 feeModule;
        uint32 executionWindow;
        bytes executionModuleData;
        bytes feeModuleData;
        bool jobIsExpired;
        bool jobInExecutionWindow;
    }

    /**
     * @notice Fetches job data  for all _indices along with the corresponding execution module data.
     * @param _indices Array of indices of jobs to query data from.
     * @return data Array of JobData structs containing information of the jobs. The job info for job at index _indices[i] will be stored in data[i].
     */
    function getJobs(uint256[] calldata _indices) external view returns (JobData[] memory);

    /**
     * @notice Fetches the executor info for the given executor in _executors.
     * @param _executors Array of addresses of executors to query data from.
     * @return data Array of Executor structs containing information of the executors. The executor info for executor at index _executors[i] will be stored in data[i].
     */
    function getExecutors(address[] calldata _executors) external view returns (ICoordinator.Executor[] memory);

    /**
     * @notice Fetches the commitment data for the given executors in _executors.
     * @param _executors Array of addresses of executors to query data from.
     * @return data Array of CommitData structs containing information of the executor's last commitment. The commitment data for executor at index _executors[i] will be stored in data[i].
     */
    function getCommitData(address[] calldata _executors) external view returns (ICoordinator.CommitData[] memory);

    /**
     * @notice Fetches the current epoch info.
     * @return epoch The current epoch number.
     * @return epochEndTime The end time of the current epoch.
     * @return seed The seed for the current epoch.
     * @return numberOfActiveExecutors The number of active executors during the epoch.
     */
    function getCurrentEpochInfo() external view returns (uint192, uint256, bytes32, uint40, address[] memory);
}
