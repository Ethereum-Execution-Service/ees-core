// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {LinearAuction} from "../../src/feeModules/LinearAuction.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";

/// @author Victor Brevig
contract MockLinearAuction is LinearAuction {
    constructor(JobRegistry _jobRegistry) LinearAuction(_jobRegistry) {}

    // Helper function to set job parameters directly for testing
    function setJobParams(
        uint256 _index,
        address _executionFeeToken,
        uint256 _minExecutionFee,
        uint256 _maxExecutionFee
    ) public {
        params[_index] = Params({
            executionFeeToken: _executionFeeToken,
            minExecutionFee: _minExecutionFee,
            maxExecutionFee: _maxExecutionFee
        });
    }
}
