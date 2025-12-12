// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IModuleRegistry} from "./interfaces/IModuleRegistry.sol";

/**
 * @title ModuleRegistry
 * @notice Manages registration of execution modules and fee modules for the EES system
 * @dev Inherits from Owned for access control. Modules are stored in a single array with a flag
 *      indicating whether they are execution or fee modules. Module indices are used to reference
 *      modules in job specifications.
 */
contract ModuleRegistry is Owned, IModuleRegistry {
    /// @notice Array of all registered modules (both execution and fee modules)
    /// @dev Each module has an address and a flag indicating if it's an execution module
    Module[] public modules;

    /**
     * @notice Initializes the ModuleRegistry contract
     * @param _owner Address that will own the contract (can add modules)
     */
    constructor(address _owner) Owned(_owner) {}

    /**
     * @notice Adds a new execution module to the registry
     * @dev Can only be called by the owner. Pushes module to the modules array with isExecutionModule = true.
     *      The module's index in the array is used to reference it in job specifications.
     * @param _module Execution module contract to register
     */
    function addExecutionModule(IExecutionModule _module) public override onlyOwner {
        modules.push(Module({module: address(_module), isExecutionModule: true}));
    }

    /**
     * @notice Adds a new fee module to the registry
     * @dev Can only be called by the owner. Pushes module to the modules array with isExecutionModule = false.
     *      The module's index in the array is used to reference it in job specifications.
     * @param _module Fee module contract to register
     */
    function addFeeModule(IFeeModule _module) public override onlyOwner {
        modules.push(Module({module: address(_module), isExecutionModule: false}));
    }
}
