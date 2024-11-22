// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the executeJob function
 */
contract JobRegistryExecuteTest is JobRegistryBaseTest {

  function test_ExecuteDeletedJob() public {
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

        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobIsDeleted.selector));
        jobRegistry.execute(index, from);
    }

    function test_ExecuteNotExecutionContract(address caller) public {
        vm.assume(caller != address(coordinator));
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

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.execute(index, from);
    }

    function test_ExecuteReachingMaxExecutions() public {
        // should inactivate a job it it reaches max executions
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
            maxExecutions: 1,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        vm.prank(address(coordinator));
        jobRegistry.execute(index, from);

        (, bool active,,,,,,,,,uint48 executionCounter,,,) = jobRegistry.jobs(index);

        assertEq(active, false, "active mismatch");
        assertEq(executionCounter, 1, "execution counter mismatch");
    }

    function test_ExecuteUnsuccessfulWithIgnore() public {
        // should inactivate a job it it reaches max executions
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
            ignoreAppRevert: true,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);

        dummyApplication.setRevertOnExecute(true);

        vm.prank(address(coordinator));
        jobRegistry.execute(index, from);

        (, bool active,,,,,,,,,uint48 executionCounter,,,) = jobRegistry.jobs(index);
        assertEq(active, true, "active mismatch");
        assertEq(executionCounter, 0, "execution counter mismatch");
    }

    function test_BalancesExecuteNoSponsor(uint256 _executionFee) public {
        uint256 startBalanceFrom = token0.balanceOf(from);
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        _executionFee = bound(_executionFee, 0, startBalanceFrom);
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

        dummyFeeModule.setExecutionFee(_executionFee);
        vm.prank(address(coordinator));
        jobRegistry.execute(index, executor);

        assertEq(token0.balanceOf(from), startBalanceFrom - _executionFee, "from balance");
        assertEq(token0.balanceOf(executor), startBalanceExecutor + _executionFee, "executor balance");
    }

    function test_BalancesExecuteWithSponsor(uint256 _executionFee) public {
        uint256 startBalanceFrom = token0.balanceOf(from);
        uint256 startBalanceSponsor = token0.balanceOf(sponsor);
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        _executionFee = bound(_executionFee, 0, startBalanceFrom);

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

        dummyFeeModule.setExecutionFee(_executionFee);
        vm.prank(address(coordinator));
        jobRegistry.execute(index, executor);

        assertEq(token0.balanceOf(from), startBalanceFrom, "from balance");
        assertEq(token0.balanceOf(sponsor), startBalanceSponsor - _executionFee, "sponsor balance");
        assertEq(token0.balanceOf(executor), startBalanceExecutor + _executionFee, "executor balance");
    }


    function test_NoMaxExecutionLimit() public {
        // Should be able to execute twice when maxExecutions is set to 0
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
        vm.prank(address(coordinator));
        jobRegistry.execute(0, from);
    }

    function test_MaxExecutionLimitOfOne() public {
        // Should revert when trying to execute more than once when maxExecutions set to 1. Job is deactivated
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
            maxExecutions: 1,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);
        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobNotActive.selector));
        jobRegistry.execute(0, from);
    }
}