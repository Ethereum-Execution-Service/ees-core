// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExecutionModule} from "../IExecutionModule.sol";

interface IRegularTimeInterval is IExecutionModule {
    struct Params {
        uint40 lastExecution;
        uint32 cooldown;
    }

    /// @notice Thrown when the caller is not authorized to the action on the job
    error Unauthorized();

    /// @notice Thrown when a job is expired
    error JobExpired();

    /// @notice Thrown when there has not been enough time past since the last payment
    error NotEnoughTimePast();

    /// @notice Thrown when the cooldown is less that the execution window of the job
    error CooldownLessThanExecutionWindow();

    /// @notice Thrown when the caller is not the set JobRegistry contract
    error NotJobRegistry();
}
