// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the updateFeeModule function
 */
contract JobRegistryUpdateFeeModuleTest is JobRegistryBaseTest {

  function test_UpdateFeeModuleWithSponsor() public {
      // Should be able to update fee module with sponsorship
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
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);
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
        (,,,,,, bytes1 feeModuleSet,,,address sponsorSet,,,,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_UpdateFeeModuleWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // Should revert with ExpiredSignature when updating fee module with an expired signature
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);
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
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);
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
        // Should be able to update fee module without sponsorship
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: UINT256_MAX,
            reusableNonce: false,
            sponsorFallbackToOwner: false,
            sponsorCanUpdateFeeModule: true,
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

        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);

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
        // Should revert with JobInExecutionMode when updating fee module of a job that is in execution mode
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
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);
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
        // Should revert with Unauthorized when updating fee module of a job from a caller that is not the owner of the job
        vm.assume(caller != from);
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
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(defaultFeeToken, 1_000_000);
        vm.prank(treasury);
        coordinator.addFeeModule(dummyFeeModule2);
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

    function test_MigrateFeeModuleWithSponsor() public {
        // Should be able to migrate fee module with sponsorship
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