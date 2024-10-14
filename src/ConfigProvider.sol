// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "./JobRegistry.sol";
import {Coordinator} from "./Coordinator.sol";
import {Querier} from "./Querier.sol";
import {BatchSlasher} from "./BatchSlasher.sol";

contract ConfigProvider {
    JobRegistry public jobRegistry;
    Coordinator public coordinator;
    Querier public querier;
    BatchSlasher public batchSlasher;

    constructor(JobRegistry _jobRegistry, Coordinator _coordinator, Querier _querier, BatchSlasher _batchSlasher) {
        jobRegistry = _jobRegistry;
        coordinator = _coordinator;
        querier = _querier;
        batchSlasher = _batchSlasher;
    }

    function getConfig() public view returns (bytes memory, bytes memory, bytes memory) {
        return (
            abi.encode(address(jobRegistry), address(coordinator), address(querier), address(batchSlasher)),
            jobRegistry.exportConfig(),
            coordinator.exportConfig()
        );
    }
}
