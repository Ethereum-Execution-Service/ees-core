// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "./JobRegistry.sol";
import {ExecutionManager} from "./ExecutionManager.sol";
import {Querier} from "./Querier.sol";

contract ConfigProvider {
    JobRegistry public jobRegistry;
    ExecutionManager public executionManager;
    Querier public querier;

    constructor(JobRegistry _jobRegistry, ExecutionManager _executionManager, Querier _querier) {
        jobRegistry = _jobRegistry;
        executionManager = _executionManager;
        querier = _querier;
    }

    function getConfig() public view returns (bytes memory, bytes memory, bytes memory) {
        return (
            abi.encode(address(jobRegistry), address(executionManager), address(querier)),
            jobRegistry.exportConfig(),
            executionManager.exportConfig()
        );
    }
}
