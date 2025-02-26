// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the updateFeeModule function
 */
contract JobRegistryUpdateFeeModuleTest is JobRegistryBaseTest {
    function test_UpdateFeeModuleWithNewSponsor() public {
        // should be able to update fee module with new sponsorship

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig);
        (,,,,,, bytes1 feeModuleSet,,, address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_UpdateFeeModuleWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // should revert with ExpiredSignature when updating fee module with an expired signature
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: deadline,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        vm.warp(createTime);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.SignatureExpired.selector, deadline));
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig);
    }

    function test_UpdateFeeModuleDataNoSponsor() public {
        // should be able to update fee module without sponsorship
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });

        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, address(0), "");
        (,,,,,, bytes1 feeModuleSet,,, address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, from, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_UpdateFeeModuleInExecutionMode() public {
        // should revert with JobInExecutionMode when updating fee module of a job that is in execution mode
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        dummyExecutionModule.setIsInExecutionMode(true);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobInExecutionMode.selector));
        jobRegistry.updateFeeModule(feeModuleInput, address(0), "");
    }

    function test_UpdateFeeModuleNotOwner(address caller) public {
        // should revert with Unauthorized when updating fee module of a job from a caller that is not the owner of the job
        vm.assume(caller != from);
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.updateFeeModule(feeModuleInput, address(0), "");
    }

    function test_UpdateFeeModuleSponsorAllowed() public {
        // sponsor should be able to update fee module if sponsorCanUpdateFeeModule is true

        genericJobSpecification.sponsorCanUpdateFeeModule = true;
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        vm.prank(sponsor);
        jobRegistry.updateFeeModule(feeModuleInput, address(0), "");
        (,,,,,, bytes1 feeModuleSet,,, address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_UpdateFeeModuleSponsorAllowedToNewSponsor() public {
        // sponsor should be able to update fee module with a new sponsorship if sponsorCanUpdateFeeModule is true

        genericJobSpecification.sponsorCanUpdateFeeModule = true;
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });

        bytes memory sponsor2Sig =
            getFeeModuleInputSignature(feeModuleInput, sponsor2PrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(sponsor);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor2, sponsor2Sig);
        (,,,,,, bytes1 feeModuleSet,,, address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor2, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_MigrateFeeModuleWithSponsor() public {
        // should be able to migrate fee module with sponsorship
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            reusableNonce: false,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x02,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig);
        (,,,,,, bytes1 feeModuleSet,,, address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x02), "fee module mismatch");
    }
}
