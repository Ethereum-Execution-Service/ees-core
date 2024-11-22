// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the deactivateJob function
 */
contract JobRegistryDeactivateTest is JobRegistryBaseTest {

  function test_DeactivateJobNotOwner(address caller) public {
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
      jobRegistry.createJob(jobSpecification, address(0), "","", UINT256_MAX);
      vm.prank(caller);
      vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
      jobRegistry.deactivateJob(0);
    }

}