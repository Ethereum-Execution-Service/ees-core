// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the createJob function
 */
contract JobRegistryCreateTest is JobRegistryBaseTest {
    function test_CreateJobWithoutSponsor() public {
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_CreateJobWithSponsor() public {
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);
    }

    function test_CreateJobWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // Should revert with SignatureExpired if deadline is in the past
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);
        genericJobSpecification.deadline = deadline;

        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(from);
        vm.warp(createTime);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.SignatureExpired.selector, deadline));
        jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);
    }

    function test_CreateJobWithSponsorReusingNonce() public {
        // Should revert with InvalidNonce if nonce is already used
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.InvalidNonce.selector));
        jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig, "", UINT256_MAX);
    }

    function test_RevertWhen_CreationWithInvalidModule() public {
        // Test case 1: Using fee module (0x01) as execution module
        genericJobSpecification.executionModule = 0x01;
        genericJobSpecification.feeModule = 0x01;

        vm.prank(from);
        vm.expectRevert(IJobRegistry.InvalidModule.selector);
        jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
    }

    function test_RevertWhen_CreationWithInvalidModule_ExecutionModuleAsFeeModule() public {
        // Test case 2: Using execution module (0x00) as fee module
        genericJobSpecification.executionModule = 0x00;
        genericJobSpecification.feeModule = 0x00;

        vm.prank(from);
        vm.expectRevert(IJobRegistry.InvalidModule.selector);
        jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
    }

    function test_CreateionReuseExpiredJobIndex(address caller) public {
        // Anyone should be able to create a new job with the same index as an expired job
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        dummyExecutionModule.expireJob();

        genericJobSpecification.nonce = 1;
        genericJobSpecification.owner = address2;
        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(genericJobSpecification, address(0), "", "", index);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);

        assertEq(index, index2, "index mismatch");
        assertEq(owner, address2, "owner mismatch");
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_CreateAndReuseDeletedJobIndex() public {
        // should be able to reuse and index of a deleted job
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);

        genericJobSpecification.nonce = 1;
        genericJobSpecification.owner = address2;
        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(genericJobSpecification, address(0), "", "", index);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);

        assertEq(index, index2, "index mismatch");
        assertEq(owner, address2, "owner mismatch");
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_ReuseJobIndexAlreadyTaken() public {
        // should revert when trying to reuse an index that is already taken
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        genericJobSpecification.nonce = 1;
        genericJobSpecification.owner = address2;
        vm.prank(address2);
        uint256 setIndex = jobRegistry.createJob(genericJobSpecification, address(0), "", "", index);
        assertEq(setIndex, 1, "index mismatch");
    }

    function test_CreateJobEndOfArray() public {
        // should be able to create a job at the end of the array
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        genericJobSpecification.nonce = 1;
        genericJobSpecification.owner = address2;
        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);
        (address owner2,,,,,,,,,,,,,) = jobRegistry.jobs(index2);

        assertEq(index, 0);
        assertEq(index2, 1);
        assertEq(owner, from);
        assertEq(owner2, address2);
    }

    function test_CreateJobInitialExecution() public {
        // Should execute once when execution module returns true for initial execution
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
        (,,,,,,,,,, uint48 executionCounter,,,) = jobRegistry.jobs(0);
        assertEq(executionCounter, 1, "execution counter mismatch");
    }

    function test_CreateJobWithOwnerSignature() public {
        // should be able to create a job with an owner signature
        bytes memory ownerSig =
            getJobSpecificationOwnerSignature(genericJobSpecification, fromPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(address2);
        jobRegistry.createJob(genericJobSpecification, address(0), "", ownerSig, UINT256_MAX);
        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(0);
        assertEq(owner, address2, "owner mismatch");
    }

    function test_CreateJobWithOwnerSignatureDeadlineExpired() public {
        // should revert with SignatureExpired if deadline is in the past
        genericJobSpecification.deadline = block.timestamp - 1;
        bytes memory ownerSig =
            getJobSpecificationOwnerSignature(genericJobSpecification, fromPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(address2);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.SignatureExpired.selector, block.timestamp - 1));
        jobRegistry.createJob(genericJobSpecification, address(0), "", ownerSig, UINT256_MAX);
    }

    function test_CreateJobWithReusingOwnerSignature() public {
        // Should revert with InvalidNonce if nonce reusing owner signature (nonce is already taken)
        bytes memory ownerSig =
            getJobSpecificationOwnerSignature(genericJobSpecification, fromPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(address2);
        jobRegistry.createJob(genericJobSpecification, address(0), "", ownerSig, UINT256_MAX);
        vm.prank(address2);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.InvalidNonce.selector));
        jobRegistry.createJob(genericJobSpecification, address(0), "", ownerSig, UINT256_MAX);
    }

    function test_InitialExecutionAndMaxExecutionsOne() public {
        // Should deactivate job after initial execution if maxExecutions is one
        genericJobSpecification.maxExecutions = 1;
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);
        (,,,,,,,,,, uint48 executionCounter,,,) = jobRegistry.jobs(0);
        assertEq(executionCounter, 1, "execution counter mismatch");
        (, bool active,,,,,,,,,,,,) = jobRegistry.jobs(0);
        assertFalse(active, "job should be inactive");
    }

    function test_UseSponsorSignatureAsOwnerSignature() public {
        // Should revert with InvalidSignature if sponsor signature is used as owner signature
        bytes memory sponsorSig = getJobSpecificationSponsorSignature(
            genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR()
        );
        vm.prank(address2);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.InvalidSignature.selector));
        jobRegistry.createJob(genericJobSpecification, address(0), "", sponsorSig, UINT256_MAX);
    }

    function test_UseOwnerSignatureAsSponsorSignature() public {
        // Should revert with InvalidSignature if owner signature is used as sponsor signature
        bytes memory ownerSig =
            getJobSpecificationOwnerSignature(genericJobSpecification, fromPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(address2);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.InvalidSignature.selector));
        jobRegistry.createJob(genericJobSpecification, from, ownerSig, ownerSig, UINT256_MAX);
    }
}
