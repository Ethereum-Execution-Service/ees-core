// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @notice Interface for the SwapSingle application performing single exact input swaps.
interface IAutoSwap {
    struct Swap {
        IUniswapV3Pool pool;
        bool zeroForOne;
        int256 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    function changeExecutionModuleSupport(bytes1 _executionModule, bool _support) external;

    event SwapExecuted(
        uint256 indexed index,
        address indexed owner,
        address indexed pool,
        bool zeroForOne,
        int256 amountIn,
        int256 amountOut,
        uint256 protocolFee
    );
    event SwapCreated(uint256 indexed index, address indexed owner, address indexed pool);
    event SwapCanceled(uint256 indexed index, address indexed owner, address indexed pool);

    /// @notice Thrown when the caller is not the JobRegistry
    error NotJobRegistry();

    /// @notice Thrown when job created with unsupported execution module
    error UnsupportedExecutionModule();

    /// @notice Thrown when amountIn is negative. Only exact in are supported.
    error AmountInNegative();
}
