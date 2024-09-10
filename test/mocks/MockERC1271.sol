// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC1271} from "../../src/interfaces/IERC1271.sol";

contract MockERC1271 is IERC1271 {
    bytes4 constant VALID_SIGNATURE = 0x1626ba7e;

    bool public returnValidSignature;

    function isValidSignature(bytes32, bytes calldata) external view override returns (bytes4) {
        if (returnValidSignature) {
            return VALID_SIGNATURE;
        }
        return 0;
    }

    function setReturnValidSignature(bool _returnValidSignature) public {
        returnValidSignature = _returnValidSignature;
    }
}
