// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the deleteJob function
 */
contract JobRegistryDeleteTest is JobRegistryBaseTest {
    function test_DeleteActiveJobAsOwner() public {
        // Should be able to delete an active job as the owner
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);
        (address owner,,,,,,,,, address sponsor,,,,) = jobRegistry.jobs(index);
        assertEq(owner, address(0));
        assertEq(sponsor, address(0));
    }

    function test_DeleteActiveJobNonOwner(address caller) public {
        // Should revert when trying to delete an active job as a non-owner
        vm.assume(caller != from);
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.deleteJob(index);
    }

    function test_DeleteJobApplicationReverts() public {
        // should not revert if the application reverts onDeleteJob
        vm.prank(from);
        uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "", "", UINT256_MAX);

        dummyApplication.setRevertOnDelete(true);

        vm.prank(from);
        jobRegistry.deleteJob(index);
        (address owner,,,,,,,,, address sponsor,,,,) = jobRegistry.jobs(index);
        assertEq(owner, address(0));
        assertEq(sponsor, address(0));
    }
}
