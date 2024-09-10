// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

library FeeModuleInputHash {
    bytes32 public constant _FEE_MODULE_INPUT_TYPEHASH = keccak256(
        "FeeModuleInput(uint256 nonce,uint256 deadline,uint256 index,bytes1 feeModule,bytes32 feeModuleInputHash)"
    );

    function hash(IJobRegistry.FeeModuleInput memory feeModuleInput) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _FEE_MODULE_INPUT_TYPEHASH,
                feeModuleInput.nonce,
                feeModuleInput.deadline,
                feeModuleInput.index,
                feeModuleInput.feeModule,
                feeModuleInput.feeModuleInput,
                keccak256(feeModuleInput.feeModuleInput)
            )
        );
    }
}
