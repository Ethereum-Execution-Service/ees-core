// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

library JobSpecificationHash {
    bytes32 public constant _JOB_SPECIFICATION_TYPEHASH = keccak256(
        "JobSpecification(address owner,uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    bytes32 public constant _JOB_SPECIFICATION_NO_OWNER_TYPEHASH = keccak256(
        "JobSpecification(uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

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
