// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the deactivateJob function
 */
contract JobRegistryDeactivateTest is JobRegistryBaseTest {

  function test_DeactivateJobAsOwner() public {
    vm.startPrank(from);
    uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
    jobRegistry.deactivateJob(index);
    vm.stopPrank();
    (, bool active,,,,,,,,,,,,) = jobRegistry.jobs(index);
    assertFalse(active, "job should be inactive");
  }

  function test_DeactivateJobNotOwner(address caller) public {
      vm.assume(caller != from);
    
      vm.prank(from);
      uint256 index = jobRegistry.createJob(genericJobSpecification, address(0), "","", UINT256_MAX);
      vm.prank(caller);
      vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
      jobRegistry.deactivateJob(index);
    }

}