// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

contract FeeModuleInputSignature {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 public constant _FEE_MODULE_INPUT_TYPEHASH = keccak256(
        "FeeModuleInput(uint256 nonce,uint256 deadline,uint256 index,bytes1 feeModule,bytes32 feeModuleInputHash)"
    );

    function getFeeModuleInputSignature(
        IJobRegistry.FeeModuleInput memory feeModuleInput,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _FEE_MODULE_INPUT_TYPEHASH,
                        feeModuleInput.nonce,
                        feeModuleInput.deadline,
                        feeModuleInput.index,
                        feeModuleInput.feeModule,
                        feeModuleInput.feeModuleInput,
                        keccak256(feeModuleInput.feeModuleInput)
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
    /*
    function getCompactFeeModuleInputSignature(
        IJobRegistry.FeeModuleInput memory feeModuleInput,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _FEE_MODULE_INPUT_TYPEHASH,
                        feeModuleInput.nonce,
                        feeModuleInput.deadline,
                        feeModuleInput.index,
                        feeModuleInput.feeModule,
                        feeModuleInput.feeModuleInput,
                        keccak256(feeModuleInput.feeModuleInput)
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        bytes32 vs;
        (r, vs) = _getCompactFeeModuleInputSignature(v, r, s);
        return bytes.concat(r, vs);
    }

    function _getCompactFeeModuleInputSignature(uint8 vRaw, bytes32 rRaw, bytes32 sRaw)
        internal
        pure
        returns (bytes32 r, bytes32 vs)
    {
        uint8 v = vRaw - 27; // 27 is 0, 28 is 1
        vs = bytes32(uint256(v) << 255) | sRaw;
        return (rRaw, vs);
    }
        */
}
