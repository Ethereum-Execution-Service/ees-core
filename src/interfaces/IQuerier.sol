// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IApplication} from "./IApplication.sol";

interface IQuerier {
    struct JobData {
        uint256 index;
        address owner;
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
}
