// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the revokeSponsorship function
 */
contract JobRegistryRevokeSponsorshipTest is JobRegistryBaseTest {
    function test_RevokeSponsorshipSponsorNoFallbackToOwner() public {
        // when sponsor revokes sponsorship with no fallback to owner, the sponsor is set to 0
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        vm.prank(sponsor);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,, address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, address(0));
    }

    function test_RevokeSponsorshipSponsorWithFallbackToOwner() public {
        // when sponsor revokes sponsorship with fallback to owner, the owner is set as sponsor
        genericJobSpecification.sponsorFallbackToOwner = true;

        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        vm.prank(sponsor);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,, address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorshipOwner() public {
        // when owner revokes sponsorship, sponsor is set to owner
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        vm.prank(from);
        jobRegistry.revokeSponsorship(index);
        (,,,,,,,,, address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorShipNotOwnerOrSponsor(address caller) public {
        // should revert if the caller is not the owner or the sponsor
        vm.assume(caller != from && caller != sponsor);

        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.revokeSponsorship(index);
    }
}
