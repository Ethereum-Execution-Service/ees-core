// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the revokeSponsorship function
 */
contract JobRegistryRevokeSponsorshipTest is JobRegistryBaseTest {

  function test_RevokeSponsorshipSponsorNoFallbackToOwner() public {
      IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
          owner: from,
          nonce: 0,
          deadline: UINT256_MAX,
          reusableNonce: false,
          sponsorFallbackToOwner: false,
          sponsorCanUpdateFeeModule: false,
          application: dummyApplication,
          executionWindow: defaultExecutionWindow,
          zeroFeeWindow: defaultZeroFeeWindow,
          ignoreAppRevert: false,
          maxExecutions: 0,
          executionModule: 0x00,
          feeModule: 0x01,
          executionModuleInput: "",
          feeModuleInput: "",
          applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        vm.prank(sponsor);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,,address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, address(0));
    }

    function test_RevokeSponsorshipSponsorWithFallbackToOwner() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: UINT256_MAX,
            reusableNonce: false,
            sponsorFallbackToOwner: true,
            sponsorCanUpdateFeeModule: false,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            zeroFeeWindow: defaultZeroFeeWindow,
            ignoreAppRevert: false,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        vm.prank(sponsor);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,,address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorshipOwner() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: UINT256_MAX,
            reusableNonce: false,
            sponsorFallbackToOwner: false,
            sponsorCanUpdateFeeModule: false,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            zeroFeeWindow: defaultZeroFeeWindow,
            ignoreAppRevert: false,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        vm.prank(from);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,,address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorShipNotOwnerOrSponsor(address caller) public {
        vm.assume(caller != from && caller != sponsor);

        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: UINT256_MAX,
            reusableNonce: false,
            sponsorFallbackToOwner: false,
            sponsorCanUpdateFeeModule: false,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            zeroFeeWindow: defaultZeroFeeWindow,
            ignoreAppRevert: false,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.revokeSponsorship(index);
    }
}