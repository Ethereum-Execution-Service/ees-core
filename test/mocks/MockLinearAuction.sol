// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LinearAuction} from "../../src/feeModules/LinearAuction.sol";
import {Coordinator} from "../../src/Coordinator.sol";

/// @author Victor Brevig
contract MockLinearAuction is LinearAuction {
    constructor(Coordinator _coordinator) LinearAuction(_coordinator) {}

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
