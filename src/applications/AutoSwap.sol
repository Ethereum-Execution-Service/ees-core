// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAutoSwap} from "../interfaces/applications/IAutoSwap.sol";
import {FeeManager} from "../FeeManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IApplication} from "../interfaces/IApplication.sol";
import {JobRegistry} from "../JobRegistry.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract AutoSwap is IAutoSwap, IApplication, FeeManager {
    using SafeTransferLib for ERC20;

    JobRegistry public immutable jobRegistry;

    mapping(uint256 => Swap) public swaps;

    // could use a bit map here
    mapping(bytes1 => bool) public supportedExecutionModules;

    modifier onlyJobRegistry() {
        if (msg.sender != address(jobRegistry)) revert NotJobRegistry();
        _;
    }

    constructor(JobRegistry _jobRegistry, address _treasury, uint16 _treasuryBasisPoints, address _owner)
        FeeManager(_owner, _treasury, _treasuryBasisPoints)
    {
        jobRegistry = _jobRegistry;
    }

    function onCreateJob(uint256 _index, bytes1 _executionModule, address _owner, bytes calldata _inputs)
        external
        override
        onlyJobRegistry
    {
        if (!supportedExecutionModules[_executionModule]) revert UnsupportedExecutionModule();
        address pool;
        bool zeroForOne;
        int256 amountIn;
        uint160 sqrtPriceLimitX96;
        assembly {
            pool := calldataload(_inputs.offset)
            zeroForOne := calldataload(add(_inputs.offset, 0x20))
            amountIn := calldataload(add(_inputs.offset, 0x40))
            sqrtPriceLimitX96 := calldataload(add(_inputs.offset, 0x60))
        }

        if (amountIn < 0) revert AmountInNegative();

        Swap memory swap = Swap({
            pool: IUniswapV3Pool(pool),
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        swaps[_index] = swap;
        emit SwapCreated(_index, _owner, pool);
    }

    function onDeleteJob(uint256 _index, address _owner) external override onlyJobRegistry {
        Swap memory swap = swaps[_index];
        delete swaps[_index];
        emit SwapCanceled(_index, _owner, address(swap.pool));
    }

    function onExecuteJob(uint256 _index, address _owner, uint48 _executionNumber) external override onlyJobRegistry {
        Swap memory swap = swaps[_index];

        uint256 protocolFee = calculateFee(uint256(swap.amountIn), treasuryFeeBasisPoints);
        uint256 remainingAmount = uint256(swap.amountIn) - protocolFee;

        address tokenIn;
        if (swap.zeroForOne) tokenIn = swap.pool.token0();
        else tokenIn = swap.pool.token1();

        // transfer protocol fee
        ERC20(tokenIn).safeTransferFrom(_owner, treasury, protocolFee);
        // transfer amount
        ERC20(tokenIn).safeTransferFrom(_owner, address(this), remainingAmount);

        (int256 amount0, int256 amount1) =
            swap.pool.swap(_owner, swap.zeroForOne, swap.amountIn, swap.sqrtPriceLimitX96, bytes(""));

        // refund remaining tokens if necessary
        if (swap.zeroForOne) {
            // when zeroForOne, amount0 must be 0 or greater (pool receives token0)
            if (uint256(amount0) < remainingAmount) {
                ERC20(tokenIn).safeTransferFrom(address(this), _owner, remainingAmount - uint256(amount0));
            }
        } else {
            // when !zeroForOne, amount1 must be 0 or greater (pool recieves token1)
            if (uint256(amount1) < remainingAmount) {
                ERC20(tokenIn).safeTransferFrom(address(this), _owner, remainingAmount - uint256(amount1));
            }
        }

        emit SwapExecuted(
            _index,
            _owner,
            address(swap.pool),
            swap.zeroForOne,
            swap.zeroForOne ? amount0 : amount1,
            swap.zeroForOne ? -amount1 : -amount0,
            protocolFee
        );
    }

    function changeExecutionModuleSupport(bytes1 _executionModule, bool _support) public override onlyOwner {
        supportedExecutionModules[_executionModule] = _support;
    }
}
