// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IFeeModule} from "../../../src/interfaces/IFeeModule.sol";
import {JobRegistry} from "../../../src/JobRegistry.sol";
import {IJobRegistry} from "../../../src/interfaces/IJobRegistry.sol";

contract DummyFeeModule is IFeeModule {
    JobRegistry public immutable jobRegistry;

    error NotJobRegistry();

    uint256 public counter;

    address internal executionFeeToken;
    uint256 internal executionFee;

    constructor(JobRegistry _jobRegistry, address _executionFeeToken, uint256 _executionFee) {
        jobRegistry = _jobRegistry;
        executionFeeToken = _executionFeeToken;
        executionFee = _executionFee;
        counter = 0;
    }

    function onCreateJob(uint256 _index, bytes calldata _inputs) external override {}

    function onDeleteJob(uint256 _index) external override {}

    function onExecuteJob(
        uint256 _index,
        address _caller,
        uint32 _executionWindow,
        uint256 _executionTime,
        uint256 _variableGasConsumption
    ) external override returns (uint256, address) {
        counter++;
        return (executionFee, executionFeeToken);
    }

    function onUpdateData(uint256 _index, bytes calldata _inputs) public override {}

    function setExecutionFee(uint256 _executionFee) public {
        executionFee = _executionFee;
    }

    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        return "";
    }
}
