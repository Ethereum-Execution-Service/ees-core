// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {IModuleRegistry} from "../../src/interfaces/IModuleRegistry.sol";

/**
 * @notice Tests for the registerModules function
 */
contract CoordinatorRegisterModulesTest is CoordinatorBaseTest {
    function test_RegisterModules() public {
        uint256 addedModule = 1 << 2;

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        uint256 startBalance = token0.balanceOf(executor);

        vm.prank(executor);
        coordinator.registerModules(addedModule);

        (uint256 balance,,,,,,,, uint256 lastRegistrationTimestamp, uint256 registeredModules) =
            coordinator.executorInfo(executor);

        assertEq(registeredModules, (1 << 0) | (1 << 1) | (1 << 2), "modules mismatch");
        assertEq(lastRegistrationTimestamp, block.timestamp, "last registration timestamp mismatch");
        assertEq(balance, stakingAmountPerModule * 3, "balance mismatch");
        assertEq(startBalance - token0.balanceOf(executor), stakingAmountPerModule, "executor balance mismatch");
    }

    function test_RegisterAlreadyRegisteredModule() public {
        // should revert if any of the modules are already registered
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.SomeModulesAlreadyRegistered.selector);
        coordinator.registerModules((1 << 0));
    }

    function test_RegisterNotInitializedExecutor(address caller) public {
        // should revert if the executor is not initialized
        vm.prank(caller);
        vm.expectRevert(ICoordinator.NotInitializedExecutor.selector);
        coordinator.registerModules((1 << 0));
    }

    function test_RegisteringZeroModules() public {
        // should revert if no modules are provided to register. Here we use out out bound modules to get an empty bitset
        uint256 addedModule = 1 << 4;

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.prank(executor);
        vm.expectRevert(IModuleRegistry.NoModulesToRegister.selector);
        coordinator.registerModules(addedModule);
    }
}
