// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IJobRegistry} from "../../../src/interfaces/IJobRegistry.sol";
import {IExecutionModule} from "../../../src/interfaces/IExecutionModule.sol";
import {IFeeModule} from "../../../src/interfaces/IFeeModule.sol";

contract DummyJobRegistry is IJobRegistry {
    bool public revertOnExecute;
    bool public jobsInZeroFeeWindow;
    uint8 public returnExecutionModule;
    uint8 public returnFeeModule;

    constructor() {
        returnExecutionModule = 0;
        returnFeeModule = 1;
    }

    function setRevertOnExecute(bool _revertOnExecute) external {
        revertOnExecute = _revertOnExecute;
    }

    function setJobsInZeroFeeWindow(bool _jobsInZeroFeeWindow) external {
        jobsInZeroFeeWindow = _jobsInZeroFeeWindow;
    }

    function setReturnExecutionModule(uint8 _returnExecutionModule) external {
        returnExecutionModule = _returnExecutionModule;
    }

    function setReturnFeeModule(uint8 _returnFeeModule) external {
        returnFeeModule = _returnFeeModule;
    }

    function createJob(
        JobSpecification calldata _specification,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bytes calldata _ownerSignature,
        uint256 _index
    ) external returns (uint256 index) {
        return 0;
    }

    function execute(uint256 _index, address _feeRecipient) external returns (uint256, address, uint8, uint8, bool) {
        if (revertOnExecute) {
            revert("DummyJobRegistry: Revert on execute");
        }
        return (0, address(0), returnExecutionModule, returnFeeModule, jobsInZeroFeeWindow);
    }

    function deleteJob(uint256 _index) external {}
    
    function deactivateJob(uint256 _index) external {}

    function activateJob(uint256 _index) external {}

    function revokeSponsorship(uint256 _index) external {}

    function addExecutionModule(IExecutionModule _module) external {}

    function addFeeModule(IFeeModule _module) external {}

    function updateFeeModule(
        FeeModuleInput calldata _feeModuleInput,
        address _sponsor,
        bytes calldata _sponsorSignature
    ) external {}

    function getJobsArrayLength() external view returns (uint256) {
        return 0;
    }
}
