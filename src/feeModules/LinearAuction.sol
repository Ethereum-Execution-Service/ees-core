// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExecutionModule} from "../interfaces/IExecutionModule.sol";
import {ILinearAuction} from "../interfaces/feeModules/ILinearAuction.sol";
import {JobRegistry} from "../JobRegistry.sol";
import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

/// @author Victor Brevig
contract LinearAuction is ILinearAuction {
    JobRegistry public immutable jobRegistry;
    mapping(uint256 => Params) public params;

    constructor(JobRegistry _jobRegistry) {
        jobRegistry = _jobRegistry;
    }

    modifier onlyJobRegistry() {
        if (msg.sender != address(jobRegistry)) revert NotJobRegistry();
        _;
    }

    /**
     * @notice Computes execution fee as a linear function between minExecutionFee and maxExecutionFee depending on time in execution window.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _executionWindow The amount of time the job can be executed within.
     * @param _executionTime The time the job can be executed from.
     * @return executionFee The computed execution fee.
     */
    function onExecuteJob(
        uint256 _index,
        address, /* _caller */
        uint32 _executionWindow,
        uint256 _executionTime,
        uint256 /* _variableGasConsumption */
    ) external override onlyJobRegistry returns (uint256 executionFee, address executionFeeToken) {
        Params memory job = params[_index];

        uint256 feeDiff;
        unchecked {
            feeDiff = job.maxExecutionFee - job.minExecutionFee;
        }
        uint256 secondsInAuctionPeriod = block.timestamp - _executionTime;

        executionFee = ((feeDiff * secondsInAuctionPeriod) / (_executionWindow - 1)) + job.minExecutionFee;
        executionFeeToken = job.executionFeeToken;

        return (executionFee, executionFeeToken);
    }

    /**
     * @notice Stores the parameters for a job in the params mapping.
     * @notice Reverts if minExecutionFee is greater than maxExecutionFee.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _inputs The encoded parameters for the job.
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
            executionFeeToken: executionFeeToken,
            minExecutionFee: minExecutionFee,
            maxExecutionFee: maxExecutionFee
        });
    }

    /**
     * @notice Updates the parameters for a job in the params mapping.
     * @notice Reverts if minExecutionFee is greater than maxExecutionFee.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _inputs The encoded parameters for the job.
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
     * @notice Deletes stored parameters from params mapping.
     * @param _index Job index to delete.
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice Returns the encoded parameters for a job.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @return encodedData The encoded parameters for the job.
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(param.executionFeeToken, param.minExecutionFee, param.maxExecutionFee);
    }
}
