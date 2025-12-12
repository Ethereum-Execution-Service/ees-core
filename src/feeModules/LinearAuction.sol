// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExecutionModule} from "../interfaces/IExecutionModule.sol";
import {ILinearAuction} from "../interfaces/feeModules/ILinearAuction.sol";
import {Coordinator} from "../Coordinator.sol";

/**
 * @title LinearAuction
 * @notice Fee module that implements a linear auction pricing model for job executions
 * @dev The execution fee increases linearly from minExecutionFee to maxExecutionFee over the
 *      execution window (after the zero fee window). During the zero fee window, execution is free.
 */
contract LinearAuction is ILinearAuction {
    /// @notice The Coordinator contract that manages this fee module
    Coordinator public immutable coordinator;

    /// @notice Mapping from job index to fee parameters (token, min fee, max fee)
    mapping(uint256 => Params) public params;

    /**
     * @notice Initializes the LinearAuction fee module
     * @param _coordinator The Coordinator contract address
     */
    constructor(Coordinator _coordinator) {
        coordinator = _coordinator;
    }

    /**
     * @notice Ensures only registered JobRegistry contracts can call module functions
     * @dev Reverts if msg.sender is not a registered JobRegistry in the Coordinator
     */
    modifier onlyJobRegistry() {
        if (!coordinator.isJobRegistry(msg.sender)) revert NotJobRegistry();
        _;
    }

    /**
     * @notice Computes the execution fee based on a linear auction model
     * @dev During the zero fee window, returns 0. After the zero fee window, the fee increases
     *      linearly from minExecutionFee to maxExecutionFee over the remaining execution window.
     *      The fee reaches maxExecutionFee at the last second of the execution window.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _executionWindow The total execution window duration (in seconds)
     * @param _zeroFeeWindow The duration of the zero fee period at the start (in seconds)
     * @param _executionTime The timestamp from which execution is allowed
     * @return executionFee The computed execution fee in the fee token
     * @return executionFeeToken The token address for the execution fee
     * @return inZeroFeeWindow True if execution is within the zero fee window
     */
    function onExecuteJob(
        uint256 _index,
        uint24 _executionWindow,
        uint24 _zeroFeeWindow,
        uint256 _executionTime,
        uint256 /* _variableGasConsumption */
    )
        external
        override
        onlyJobRegistry
        returns (uint256 executionFee, address executionFeeToken, bool inZeroFeeWindow)
    {
        Params memory job = params[_index];
        executionFeeToken = job.executionFeeToken;

        if (block.timestamp - _executionTime < _zeroFeeWindow) {
            // if the job is within the zero fee window, the execution fee is 0
            executionFee = 0;
            inZeroFeeWindow = true;
        } else {
            // else calculate fee as a linear function between minExecutionFee and maxExecutionFee over _executionWindow, starting from _zeroFeeWindow
            uint256 feeDiff;
            uint256 windowDiff;
            unchecked {
                // job creation ensures maxExecutionFee >= minExecutionFee and _executionWindow > _zeroFeeWindow
                feeDiff = job.maxExecutionFee - job.minExecutionFee;
                windowDiff = _executionWindow - _zeroFeeWindow - 1;
            }

            uint256 secondsAfterZeroFeeWindow = block.timestamp - (_executionTime + _zeroFeeWindow);
            // reaches maxExecutionFee at _executionTime + _executionWindow - 1, the last timestep that the job can be executed
            executionFee = ((feeDiff * secondsAfterZeroFeeWindow) / windowDiff) + job.minExecutionFee;
            inZeroFeeWindow = false;
        }
    }

    /**
     * @notice Stores the fee parameters for a job when it is created
     * @dev Decodes the input bytes to extract executionFeeToken, minExecutionFee, and maxExecutionFee.
     *      Validates that minExecutionFee <= maxExecutionFee.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _inputs Encoded parameters: executionFeeToken (address), minExecutionFee (uint256), maxExecutionFee (uint256)
     * @custom:reverts MinExecutionFeeGreaterThanMax if minExecutionFee > maxExecutionFee
     */
    function onCreateJob(uint256 _index, bytes calldata _inputs) external override onlyJobRegistry {
        address executionFeeToken;
        uint256 minExecutionFee;
        uint256 maxExecutionFee;
        assembly {
            executionFeeToken := calldataload(_inputs.offset)
            minExecutionFee := calldataload(add(_inputs.offset, 0x20))
            maxExecutionFee := calldataload(add(_inputs.offset, 0x40))
        }

        if (minExecutionFee > maxExecutionFee) revert MinExecutionFeeGreaterThanMax();

        params[_index] = Params({
            executionFeeToken: executionFeeToken, minExecutionFee: minExecutionFee, maxExecutionFee: maxExecutionFee
        });
    }

    /**
     * @notice Updates the fee parameters for an existing job
     * @dev Decodes the input bytes and updates the stored parameters. Validates that minExecutionFee <= maxExecutionFee.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _inputs Encoded parameters: executionFeeToken (address), minExecutionFee (uint256), maxExecutionFee (uint256)
     * @custom:reverts MinExecutionFeeGreaterThanMax if minExecutionFee > maxExecutionFee
     */
    function onUpdateData(uint256 _index, bytes calldata _inputs) external override onlyJobRegistry {
        address executionFeeToken;
        uint256 minExecutionFee;
        uint256 maxExecutionFee;
        assembly {
            executionFeeToken := calldataload(_inputs.offset)
            minExecutionFee := calldataload(add(_inputs.offset, 0x20))
            maxExecutionFee := calldataload(add(_inputs.offset, 0x40))
        }
        if (minExecutionFee > maxExecutionFee) revert MinExecutionFeeGreaterThanMax();

        Params storage job = params[_index];
        job.executionFeeToken = executionFeeToken;
        job.minExecutionFee = minExecutionFee;
        job.maxExecutionFee = maxExecutionFee;
    }

    /**
     * @notice Deletes the fee parameters for a job when it is deleted
     * @param _index The index of the job in the jobs array in JobRegistry contract
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice Returns the encoded parameters for a job
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @return encodedData ABI-encoded parameters: (executionFeeToken, minExecutionFee, maxExecutionFee)
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(param.executionFeeToken, param.minExecutionFee, param.maxExecutionFee);
    }
}
