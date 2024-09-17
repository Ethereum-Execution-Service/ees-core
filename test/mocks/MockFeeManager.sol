// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FeeManager} from "../../src/FeeManager.sol";
/// @author Victor Brevig

contract MockFeeManager is FeeManager {
    constructor(address _treasury, uint8 _protocolFeeRatio) FeeManager(_treasury, _protocolFeeRatio) {}

    function setFeeBalance(address _account, uint256 _amount, address _token) public {
        feeBalances[_account][_token] = _amount;
    }

    function getProtocolFeeRatio() public view returns (uint8) {
        return protocolFeeRatio;
    }
}
