// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {PeggedLinearAuction} from "../../src/feeModules/PeggedLinearAuction.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

/// @author Victor Brevig
contract MockPeggedLinearAuction is PeggedLinearAuction {
    constructor(JobRegistry _jobRegistry) PeggedLinearAuction(_jobRegistry) {}

    // Helper function to set job parameters directly for testing
    function setJobParams(
        uint256 _index,
        address _executionFeeToken,
        IPriceOracle _priceOracle,
        uint48 _minOverheadBps,
        uint48 _maxOverheadBps,
        bytes calldata _oracleData
    ) public {
        params[_index] = Params({
            executionFeeToken: _executionFeeToken,
            priceOracle: _priceOracle,
            minOverheadBps: _minOverheadBps,
            maxOverheadBps: _maxOverheadBps,
            oracleData: _oracleData
        });
    }
}
