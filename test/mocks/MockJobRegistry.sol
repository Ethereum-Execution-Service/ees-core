// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "../../src/JobRegistry.sol";

/// @author Victor Brevig
contract MockJobRegistry is JobRegistry {
    constructor(address _treasury, address _executionContract) JobRegistry(_treasury, _executionContract) {}

    bool revertOnExecute;

    function setRevertOnExecute(bool _revertOnExecute) public {
        revertOnExecute = _revertOnExecute;
    }

    function useUnorderedNonce(address from, uint256 nonce) public {
        _useUnorderedNonce(from, nonce);
    }
}
