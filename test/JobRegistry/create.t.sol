// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the createJob function
 */
contract JobRegistryCreateTest is JobRegistryBaseTest {
    
    function test_CreateJobWithoutSponsor() public {
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

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, address(0), "", "", UINT256_MAX);
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_CreateJobWithSponsor() public {
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
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);
    }

    function test_CreateJobWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // Should revert with SignatureExpired if deadline is in the past
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: deadline,
            reusableNonce: false,
            sponsorFallbackToOwner: false,
            sponsorCanUpdateFeeModule: false,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            zeroFeeWindow: defaultZeroFeeWindow,
            maxExecutions: 0,
            ignoreAppRevert: false,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        vm.warp(createTime);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.SignatureExpired.selector, deadline));
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);
    }

    function test_CreateJobWithSponsorReusingNonce() public {
        // Should revert with InvalidNonce if nonce is already used
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
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.InvalidNonce.selector));
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig,"", UINT256_MAX);
    }

    function testFail_CreationWithUnsupportedExecutionModule(bytes1 module) public {
        vm.assume(module != 0x00);
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
            maxExecutions: 0,
            ignoreAppRevert: false,
            executionModule: module,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);
    }

    function testFail_CreationWithUnsupportedModule(bytes1 executionModule, bytes1 feeModule) public {
        vm.assume(executionModule != 0x00 && executionModule != 0x01 && feeModule != 0x00 && feeModule != 0x01);
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
            executionModule: executionModule,
            feeModule: feeModule,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);
    }

    function test_CreateionReuseExpiredJobIndex(address caller) public {
        // Anyone should be able to create a new job with the same index as an expired job
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
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        dummyExecutionModule.expireJob();

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            owner: address2,
            nonce: 1,
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

        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(jobSpecification2, address(0), "","", index);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);

        assertEq(index, index2, "index mismatch");
        assertEq(owner, address2, "owner mismatch");
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }


    function test_CreateAndReuseDeletedJobIndex() public {
        // should be able to reuse and index of a deleted job
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

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            owner: address2,
            nonce: 1,
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

        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(jobSpecification2, address(0), "","", index);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);

        assertEq(index, index2, "index mismatch");
        assertEq(owner, address2, "owner mismatch");
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_ReuseJobIndexAlreadyTaken() public {
        // should revert when trying to reuse an index that is already taken
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

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            owner: address2,
            nonce: 1,
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

        vm.prank(address2);
        uint256 setIndex = jobRegistry.createJob(jobSpecification2, address(0), "","", index);
        assertEq(setIndex, 1, "index mismatch");
    }

    function test_CreateJobEndOfArray() public {
        // should be able to create a job at the end of the array
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

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            owner: address2,
            nonce: 1,
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

        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(jobSpecification2, address(0), "","", UINT256_MAX);

        (address owner,,,,,,,,,,,,,) = jobRegistry.jobs(index);
        (address owner2,,,,,,,,,,,,,) = jobRegistry.jobs(index2);

        assertEq(index, 0);
        assertEq(index2, 1);
        assertEq(owner, from);
        assertEq(owner2, address2);
    }

    function test_CreateJobInitialExecution() public {
        // Should execute once when execution module returns true for initial execution
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
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);
        (,,,,,,,,,, uint48 executionCounter,,,) = jobRegistry.jobs(0);
        assertEq(executionCounter, 1, "execution counter mismatch");
    }

}