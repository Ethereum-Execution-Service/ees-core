// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

library JobSpecificationHash {
    bytes32 public constant _JOB_SPECIFICATION_TYPEHASH = keccak256(
        "JobSpecification(uint256 nonce,uint256 deadline,address application,uint32 executionWindow,uint48 maxExecutions,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    function hash(IJobRegistry.JobSpecification memory specification) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _JOB_SPECIFICATION_TYPEHASH,
                specification.nonce,
                specification.deadline,
                specification.application,
                specification.executionWindow,
                specification.maxExecutions,
                specification.executionModule,
                specification.feeModule,
                keccak256(specification.executionModuleInput),
                keccak256(specification.feeModuleInput),
                keccak256(specification.applicationInput)
            )
        );
    }
}
