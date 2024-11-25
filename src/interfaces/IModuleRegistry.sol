// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExecutionModule} from "./IExecutionModule.sol";
import {IFeeModule} from "./IFeeModule.sol";

interface IModuleRegistry {

    struct Module {
        address module;
        // true if execution module, false if fee module
        bool isExecutionModule;
    }

    /**
     * @notice Adds an execution module to the registry.
     * @param _module The execution module to add.
     */
    function addExecutionModule(IExecutionModule _module) external;

    /**
     * @notice Adds a fee module to the registry.
     * @param _module The fee module to add.
     */
    function addFeeModule(IFeeModule _module) external;


    error SomeModulesAlreadyRegistered();
    error NumberOfRegisteredModulesBelowMinimum();
    error NoModulesToRegister();
    error MinimumRegistrationPeriodNotOver();
}
