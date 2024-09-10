// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";

contract SignatureGenerator {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function generateSignature(bytes32 _msgHash, uint256 _privateKey) public returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, _msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function generateCompactSignature(bytes32 _msgHash, uint256 _privateKey) public returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, _msgHash);
        bytes32 vs;
        (r, vs) = _getCompactSignature(v, r, s);
        return bytes.concat(r, vs);
    }

    function _getCompactSignature(uint8 vRaw, bytes32 rRaw, bytes32 sRaw)
        internal
        pure
        returns (bytes32 r, bytes32 vs)
    {
        uint8 v = vRaw - 27; // 27 is 0, 28 is 1
        vs = bytes32(uint256(v) << 255) | sRaw;
        return (rRaw, vs);
    }
}
