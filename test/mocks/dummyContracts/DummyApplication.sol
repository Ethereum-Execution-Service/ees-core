// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IApplication} from "../../../src/interfaces/IApplication.sol";
import {JobRegistry} from "../../../src/JobRegistry.sol";
import {IJobRegistry} from "../../../src/interfaces/IJobRegistry.sol";

contract DummyApplication is IApplication {
    JobRegistry public immutable jobRegistry;

    uint256 public counter;
    bool revertOnDelete;

    constructor(JobRegistry _jobRegistry) {
        jobRegistry = _jobRegistry;
        counter = 0;
        revertOnDelete = false;
    }

    function onCreateJob(uint256 _index, bytes1 _executionModule, address _owner, bytes calldata _inputs)
        external
        override
    {}

    function onDeleteJob(uint256 _index, address _owner) external override {
        if (revertOnDelete) {
            revert("DummyApplication: onDeleteJob failed");
        }
    }

    function onExecuteJob(uint256 _index, address _owner, uint48 _executionNumber) external override {
        counter++;
    }

    function setRevertOnDelete(bool _revertOnDelete) public {
        revertOnDelete = _revertOnDelete;
    }
}
