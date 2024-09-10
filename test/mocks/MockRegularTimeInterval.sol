// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {RegularTimeInterval} from "../../src/executionModules/RegularTimeInterval.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
/// @author Victor Brevig

contract MockRegularTimeInterval is RegularTimeInterval {
    constructor(JobRegistry _jobRegistry) RegularTimeInterval(_jobRegistry) {}

    // Helper function to set job parameters directly for testing
    function setJobParams(uint256 _index, uint40 _lastExecution, uint32 _cooldown) public {
        params[_index] = Params({lastExecution: _lastExecution, cooldown: _cooldown});
    }
}
