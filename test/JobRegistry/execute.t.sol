// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the executeJob function
 */
contract JobRegistryExecuteTest is JobRegistryBaseTest {

  function test_ExecuteDeletedJob() public {
        // should revert if the job is deleted
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
        
        vm.prank(from);
        jobRegistry.deleteJob(index);

        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobIsDeleted.selector));
        jobRegistry.execute(index, from);
    }

    function test_ExecuteNotActiveJob() public {
        // should revert if the job is not active
        vm.startPrank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
        jobRegistry.deactivateJob(index);
        vm.stopPrank();

        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobNotActive.selector));
        jobRegistry.execute(index, from);
    }

    function test_ExecuteNotCoordinatorContract(address caller) public {
        // should revert if the caller is not the coordinator contract
        vm.assume(caller != address(coordinator));
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.execute(index, from);
    }

    function test_ExecuteReachingMaxExecutions() public {
        // should inactivate a job it it reaches max executions
        genericJobSpecification.maxExecutions = 1;
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);

        vm.prank(address(coordinator));
        jobRegistry.execute(index, from);

        (, bool active,,,,,,,,,uint48 executionCounter,,,) = jobRegistry.jobs(index);

        assertEq(active, false, "active mismatch");
        assertEq(executionCounter, 1, "execution counter mismatch");
    }

    function test_ExecuteUnsuccessfulWithIgnore() public {
        // should inactivate a job it it reaches max executions
        genericJobSpecification.ignoreAppRevert = true;
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);

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

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);

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

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        dummyFeeModule.setExecutionFee(_executionFee);
        vm.prank(address(coordinator));
        jobRegistry.execute(index, executor);

        assertEq(token0.balanceOf(from), startBalanceFrom, "from balance");
        assertEq(token0.balanceOf(sponsor), startBalanceSponsor - _executionFee, "sponsor balance");
        assertEq(token0.balanceOf(executor), startBalanceExecutor + _executionFee, "executor balance");
    }


    function test_NoMaxExecutionLimit() public {
        // Should be able to execute twice when maxExecutions is set to 0
        genericJobSpecification.maxExecutions = 0;
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
        vm.prank(address(coordinator));
        jobRegistry.execute(0, from);
    }

    function test_MaxExecutionPastLimit() public {
        // Should revert when trying to execute more than once when maxExecutions set to 1. Job is deactivated
        genericJobSpecification.maxExecutions = 1;
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobNotActive.selector));
        jobRegistry.execute(0, from);
    }

    function test_FeeFallbackToOwner() public {
        // should fallback to owner if fee module fails and set the sponsor to owner
        genericJobSpecification.sponsorFallbackToOwner = true;

        uint256 startBalanceFrom = token0.balanceOf(from);
        dummyFeeModule.setExecutionFee(100);

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        // drain sponsor balance
        vm.startPrank(sponsor);
        token0.transfer(address(0), token0.balanceOf(sponsor));
        vm.stopPrank();

        vm.prank(address(coordinator));
        jobRegistry.execute(index, address2);

        (,,,,,,,,,address sponsorSet,,,,) = jobRegistry.jobs(index);

        assertEq(token0.balanceOf(sponsor), 0, "sponsor balance");
        assertEq(token0.balanceOf(from), startBalanceFrom - 100, "from balance");
        assertEq(token0.balanceOf(address2), 100, "address2 balance");
        assertEq(sponsorSet, from, "sponsor mismatch");
    }

    function test_FailedSponsorTransferNoFallback() public {
        // should revert if fee module fails and sponsorFallbackToOwner is false
        genericJobSpecification.sponsorFallbackToOwner = false;

        dummyFeeModule.setExecutionFee(100);

        bytes memory sponsorSig =
            getJobSpecificationSponsorSignature(genericJobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, sponsor, sponsorSig,"", UINT256_MAX);

        // drain sponsor balance
        vm.startPrank(sponsor);
        token0.transfer(address(0), token0.balanceOf(sponsor));
        vm.stopPrank();

        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.TransferFailed.selector));
        jobRegistry.execute(index, address2);
    }
}