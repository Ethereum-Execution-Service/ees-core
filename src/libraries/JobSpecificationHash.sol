// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

/**
 * @title JobSpecificationHash
 * @notice Library for computing EIP-712 compatible hashes of JobSpecification structs
 * @dev Provides two hashing functions: one that includes the owner field and one that excludes it.
 *      Used for signature verification when creating jobs.
 */
library JobSpecificationHash {
    /// @notice EIP-712 typehash for JobSpecification struct (with owner field)
    bytes32 public constant _JOB_SPECIFICATION_TYPEHASH = keccak256(
        "JobSpecification(address owner,uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    /// @notice EIP-712 typehash for JobSpecification struct (without owner field)
    bytes32 public constant _JOB_SPECIFICATION_NO_OWNER_TYPEHASH = keccak256(
        "JobSpecification(uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    /**
     * @notice Computes the EIP-712 hash of a JobSpecification struct including the owner field
     * @dev Hashes all fields of the struct including owner, and hashes nested byte arrays
     *      (executionModuleInput, feeModuleInput, applicationInput) before encoding
     * @param specification The JobSpecification struct to hash
     * @return The keccak256 hash of the encoded struct
     */
    function hash(IJobRegistry.JobSpecification memory specification) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _JOB_SPECIFICATION_TYPEHASH,
                specification.owner,
                specification.nonce,
                specification.deadline,
                specification.reusableNonce,
                specification.sponsorFallbackToOwner,
                specification.sponsorCanUpdateFeeModule,
                specification.application,
                specification.executionWindow,
                specification.zeroFeeWindow,
                specification.maxExecutions,
                specification.ignoreAppRevert,
                specification.executionModule,
                specification.feeModule,
                keccak256(specification.executionModuleInput),
                keccak256(specification.feeModuleInput),
                keccak256(specification.applicationInput)
            )
        );
    }

    /**
     * @notice Computes the EIP-712 hash of a JobSpecification struct excluding the owner field
     * @dev Same as hash() but omits the owner field. Used when the owner is derived from the signature
     *      rather than being explicitly specified in the struct.
     * @param specification The JobSpecification struct to hash (owner field is ignored)
     * @return The keccak256 hash of the encoded struct
     */
    function hashNoOwner(IJobRegistry.JobSpecification memory specification) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _JOB_SPECIFICATION_NO_OWNER_TYPEHASH,
                specification.nonce,
                specification.deadline,
                specification.reusableNonce,
                specification.sponsorFallbackToOwner,
                specification.sponsorCanUpdateFeeModule,
                specification.application,
                specification.executionWindow,
                specification.zeroFeeWindow,
                specification.maxExecutions,
                specification.ignoreAppRevert,
                specification.executionModule,
                specification.feeModule,
                keccak256(specification.executionModuleInput),
                keccak256(specification.feeModuleInput),
                keccak256(specification.applicationInput)
            )
        );
    }
}
