// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeModule} from "../IFeeModule.sol";

interface ILinearAuction is IFeeModule {
    struct Params {
        address executionFeeToken;
        uint256 minExecutionFee;
        uint256 maxExecutionFee;
    }

    /// @notice Thrown when the caller is not authorized to the action on the job
    error Unauthorized();

    /// @notice Thrown auction time has passed
    error JobExpired();

    /// @notice Thrown when there has not been enough time past since the last payment
    error NotEnoughTimePast();

    /// @notice Thrown when maximum execution fee is exceeded
    error ExceedingMaxExecutionFee();

    /// @notice Thrown when the job is in auction mode
    error InExecutionMode();

    /// @notice Thrown when the minimum execution fee is greater than the maximum execution fee
    error MinExecutionFeeGreaterThanMax();

    /// @notice Thrown when execution time given is less than current timestamp
    error ExecutionTimePassed();

    /// @notice Thrown when the caller is not the set JobRegistry contract
    error NotJobRegistry();
}
