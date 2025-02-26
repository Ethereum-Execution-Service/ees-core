// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExecutionModule} from "../../../src/interfaces/IExecutionModule.sol";

contract DummyExecutionModule is IExecutionModule {
    uint256 public counter;

    bool internal jobExpired;
    bool internal isInExecutionMode;
    bool internal initialExecution;

    constructor() {
        counter = 0;
        jobExpired = false;
        isInExecutionMode = false;
        initialExecution = false;
    }

    function onCreateJob(uint256 _index, bytes calldata _inputs, uint32 _executionWindow)
        external
        override
        returns (bool)
    {
        return initialExecution;
    }

    function onDeleteJob(uint256 _index) external override {}

    function onExecuteJob(uint256 _index, uint32 _executionWindow) external override returns (uint256) {
        counter++;
        return (type(uint256).max);
    }

    function jobIsExpired(uint256 _index, uint32 _executionWindow) external view override returns (bool) {
        return jobExpired;
    }

    function jobIsInExecutionMode(uint256 _index, uint32 _executionWindow) public view override returns (bool) {
        return isInExecutionMode;
    }

    function expireJob() public {
        jobExpired = true;
    }

    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        return "";
    }

    function setIsInExecutionMode(bool _isInExecutionMode) public {
        isInExecutionMode = _isInExecutionMode;
    }

    function setInitialExecution(bool _initialExecution) public {
        initialExecution = _initialExecution;
    }
}
