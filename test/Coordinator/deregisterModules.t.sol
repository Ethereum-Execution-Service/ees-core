// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {IModuleRegistry} from "../../src/interfaces/IModuleRegistry.sol";

/**
 * @notice Tests for the deregisterModules function
 */
contract CoordinatorDeregisterModulesTest is CoordinatorBaseTest {
    function test_DeregisterModules() public {
        uint256 moduleToDeregister = 1 << 1;

        vm.prank(executor);
        coordinator.stake((1 << 0) | (1 << 1) | (1 << 2));

        vm.warp(block.timestamp + minimumRegistrationPeriod + 1);
        vm.prank(executor);
        coordinator.deregisterModules(moduleToDeregister);

        (,,,,,,,,, uint256 registeredModules) = coordinator.executorInfo(executor);

        assertEq(registeredModules, (1 << 0) | (1 << 2), "modules mismatch");
    }

    function test_DeregisterModulesBeforeMinimumRegistrationPeriod(uint256 timeToAdd) public {
        timeToAdd = bound(timeToAdd, 1, minimumRegistrationPeriod - 1);
        uint256 moduleToDeregister = 1 << 1;

        vm.prank(executor);
        coordinator.stake((1 << 0) | (1 << 1) | (1 << 2));

        vm.warp(block.timestamp + timeToAdd);

        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.MinimumRegistrationPeriodNotOver.selector);
        coordinator.deregisterModules(moduleToDeregister);
    }

    function test_DeregisterModulesWithLessThanTwoModules() public {
        uint256 moduleToDeregister = 1 << 1;

        vm.prank(executor);
        coordinator.stake((1 << 0) | (1 << 1));

        vm.warp(block.timestamp + minimumRegistrationPeriod + 1);

        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.NumberOfRegisteredModulesBelowMinimum.selector);
        coordinator.deregisterModules(moduleToDeregister);
    }

    function test_DeregisterToBelowTwoModules() public {
        uint256 moduleToDeregister = (1 << 0) | (1 << 1);

        vm.prank(executor);
        coordinator.stake((1 << 0) | (1 << 1) | (1 << 2));

        vm.warp(block.timestamp + minimumRegistrationPeriod + 1);
        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.NumberOfRegisteredModulesBelowMinimum.selector);
        coordinator.deregisterModules(moduleToDeregister);
    }

    function test_DeregisterNotInitializedExecutor() public {
        uint256 moduleToDeregister = 1 << 1;

        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotInitializedExecutor.selector);
        coordinator.deregisterModules(moduleToDeregister);
    }
}
