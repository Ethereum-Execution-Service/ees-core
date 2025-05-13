// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RegularTimeInterval} from "../../src/executionModules/RegularTimeInterval.sol";
import {Coordinator} from "../../src/Coordinator.sol";

/// @author 0xst4ck
contract MockRegularTimeInterval is RegularTimeInterval {
    constructor(Coordinator _coordinator) RegularTimeInterval(_coordinator) {}

    // Helper function to set job parameters directly for testing
    function setJobParams(uint256 _index, uint40 _lastExecution, uint32 _cooldown) public {
        params[_index] = Params({lastExecution: _lastExecution, cooldown: _cooldown});
    }
}
