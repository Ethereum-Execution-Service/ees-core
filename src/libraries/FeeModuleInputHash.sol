// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

/**
 * @title FeeModuleInputHash
 * @notice Library for computing EIP-712 compatible hashes of FeeModuleInput structs
 * @dev Used for signature verification of fee module inputs in job specifications
 */
library FeeModuleInputHash {
    /// @notice EIP-712 typehash for FeeModuleInput struct
    bytes32 public constant _FEE_MODULE_INPUT_TYPEHASH = keccak256(
        "FeeModuleInput(uint256 nonce,uint256 deadline,bool reusableNonce,uint256 index,bytes1 feeModule,bytes32 feeModuleInputHash)"
    );

    /**
     * @notice Computes the EIP-712 hash of a FeeModuleInput struct
     * @dev Hashes all fields of the struct including the nested feeModuleInput bytes
     * @param feeModuleInput The FeeModuleInput struct to hash
     * @return The keccak256 hash of the encoded struct
     */
    function hash(IJobRegistry.FeeModuleInput memory feeModuleInput) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _FEE_MODULE_INPUT_TYPEHASH,
                feeModuleInput.nonce,
                feeModuleInput.deadline,
                feeModuleInput.reusableNonce,
                feeModuleInput.index,
                feeModuleInput.feeModule,
                feeModuleInput.feeModuleInput,
                keccak256(feeModuleInput.feeModuleInput)
            )
        );
    }
}
