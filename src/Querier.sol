// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IQuerier} from "./interfaces/IQuerier.sol";
import {JobRegistry} from "./JobRegistry.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IApplication} from "./interfaces/IApplication.sol";

contract Querier is IQuerier {
    JobRegistry jobRegistry;

    constructor(JobRegistry _jobRegistry) {
        jobRegistry = _jobRegistry;
    }

    function getJobs(uint256[] calldata _indices) public view override returns (JobData[] memory) {
        JobData[] memory jobsData = new JobData[](_indices.length);
        for (uint256 i; i < _indices.length;) {
            uint256 index = _indices[i];
            (
                address owner,
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
}
