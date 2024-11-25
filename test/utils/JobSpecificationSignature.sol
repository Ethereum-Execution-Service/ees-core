// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Vm} from "forge-std/src/Vm.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

contract JobSpecificationSignature {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 public constant _JOB_SPECIFICATION_TYPEHASH = keccak256(
        "JobSpecification(address owner,uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    bytes32 public constant _JOB_SPECIFICATION_NO_OWNER_TYPEHASH = keccak256(
        "JobSpecification(uint256 nonce,uint256 deadline,bool reusableNonce,bool sponsorFallbackToOwner,bool sponsorCanUpdateFeeModule,address application,uint24 executionWindow,uint24 zeroFeeWindow,uint48 maxExecutions,bool ignoreAppRevert,bytes1 executionModule,bytes1 feeModule,bytes32 executionModuleInputHash,bytes32 feeModuleInputHash,bytes32 applicationInputHash)"
    );

    function getJobSpecificationOwnerSignature(
        IJobRegistry.JobSpecification memory jobSpecification,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _JOB_SPECIFICATION_TYPEHASH,
                        jobSpecification.owner,
                        jobSpecification.nonce,
                        jobSpecification.deadline,
                        jobSpecification.reusableNonce,
                        jobSpecification.sponsorFallbackToOwner,
                        jobSpecification.sponsorCanUpdateFeeModule,
                        jobSpecification.application,
                        jobSpecification.executionWindow,
                        jobSpecification.zeroFeeWindow,
                        jobSpecification.maxExecutions,
                        jobSpecification.ignoreAppRevert,
                        jobSpecification.executionModule,
                        jobSpecification.feeModule,
                        keccak256(jobSpecification.executionModuleInput),
                        keccak256(jobSpecification.feeModuleInput),
                        keccak256(jobSpecification.applicationInput)
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getJobSpecificationSponsorSignature(
        IJobRegistry.JobSpecification memory jobSpecification,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _JOB_SPECIFICATION_NO_OWNER_TYPEHASH,
                        jobSpecification.nonce,
                        jobSpecification.deadline,
                        jobSpecification.reusableNonce,
                        jobSpecification.sponsorFallbackToOwner,
                        jobSpecification.sponsorCanUpdateFeeModule,
                        jobSpecification.application,
                        jobSpecification.executionWindow,
                        jobSpecification.zeroFeeWindow,
                        jobSpecification.maxExecutions,
                        jobSpecification.ignoreAppRevert,
                        jobSpecification.executionModule,
                        jobSpecification.feeModule,
                        keccak256(jobSpecification.executionModuleInput),
                        keccak256(jobSpecification.feeModuleInput),
                        keccak256(jobSpecification.applicationInput)
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }


    /*
    function getCompactJobSpecificationSignature(
        IJobRegistry.JobSpecification memory jobSpecification,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _JOB_SPECIFICATION_TYPEHASH,
                        jobSpecification.nonce,
                        jobSpecification.deadline,
                        jobSpecification.application,
                        jobSpecification.executionWindow,
                        jobSpecification.maxExecutions,
                        jobSpecification.executionModule,
                        jobSpecification.feeModule,
                        keccak256(jobSpecification.executionModuleInput),
                        keccak256(jobSpecification.feeModuleInput),
                        keccak256(jobSpecification.applicationInput)
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        bytes32 vs;
        (r, vs) = _getCompactJobSpecificationSignature(v, r, s);
        return bytes.concat(r, vs);
    }

    function _getCompactJobSpecificationSignature(uint8 vRaw, bytes32 rRaw, bytes32 sRaw)
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
