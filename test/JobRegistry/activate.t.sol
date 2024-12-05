// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the activateJob function
 */
contract JobRegistryActivateTest is JobRegistryBaseTest {

  function test_ActivateJobAsOwner() public {
    vm.startPrank(from);
    uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
    // deactivate job first
    jobRegistry.deactivateJob(index);
    
    jobRegistry.activateJob(index);
    vm.stopPrank();
    (, bool active,,,,,,,,,,,,) = jobRegistry.jobs(index);
    assertTrue(active, "job should be active");
  }

  function test_ActivateJobNotOwner(address caller) public {
      vm.assume(caller != from);
    
      vm.prank(from);
      uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
      vm.prank(caller);
      vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
      jobRegistry.activateJob(index);
    }

}