// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IModuleRegistry} from "./interfaces/IModuleRegistry.sol";

/// @author 0xst4ck
/// @notice ModuleRegistry is responsible for handling module registration and managementfor EES.
contract ModuleRegistry is Owned, IModuleRegistry {
    constructor(address _owner) Owned(_owner) {}

    Module[] public modules;

    /**
     * @notice Pushes an execution module to the executionModules array.
     * @notice Only callable by the owner.
     * @param _module Execution module to be added.
     */
    function addExecutionModule(IExecutionModule _module) public override onlyOwner {
        modules.push(Module({module: address(_module), isExecutionModule: true}));
    }

    /**
     * @notice Pushes a fee module to the feeModules array.
     * @notice Only callable by the owner.
     * @param _module Fee module to be added.
     */
    function addFeeModule(IFeeModule _module) public override onlyOwner {
        modules.push(Module({module: address(_module), isExecutionModule: false}));
    }
}
