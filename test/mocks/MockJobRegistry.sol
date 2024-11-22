// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "../../src/JobRegistry.sol";
import {Coordinator} from "../../src/Coordinator.sol";
import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";
/// @author Victor Brevig
contract MockJobRegistry is JobRegistry {
    constructor(Coordinator _coordinator, PublicERC6492Validator _publicERC6492Validator) JobRegistry(_coordinator, _publicERC6492Validator) {}

    bool revertOnExecute;

    function setRevertOnExecute(bool _revertOnExecute) public {
        revertOnExecute = _revertOnExecute;
    }

    function useUnorderedNonce(address from, uint256 nonce, bool reusableNonce) public {
        _useUnorderedNonce(from, nonce, reusableNonce);
    }

}
