// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "../../src/JobRegistry.sol";

/// @author Victor Brevig
contract MockJobRegistry is JobRegistry {
    constructor(address _owner, address _treasury, uint8 _protocolFeeRatio)
        JobRegistry(_owner, _treasury, _protocolFeeRatio)
    {}

    function useUnorderedNonce(address from, uint256 nonce) public {
        _useUnorderedNonce(from, nonce);
    }
}
