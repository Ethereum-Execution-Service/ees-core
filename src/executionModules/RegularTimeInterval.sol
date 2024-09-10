// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IRegularTimeInterval} from "../interfaces/executionModules/IRegularTimeInterval.sol";
import {JobRegistry} from "../JobRegistry.sol";
import {IJobRegistry} from "../interfaces/IJobRegistry.sol";

/// @author Victor Brevig
contract RegularTimeInterval is IRegularTimeInterval {
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
     * @notice Computes the next execution time for a job.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _executionWindow The amount of time the job can be executed within.
     * @return executionTime The time the job can be executed from.
     */
    function onExecuteJob(uint256 _index, uint32 _executionWindow, bytes calldata /* _verificationData */ )
        external
        override
        onlyJobRegistry
        returns (uint256 executionTime)
    {
        Params storage job = params[_index];
        uint40 nextExecution = job.lastExecution + job.cooldown;
        if (block.timestamp < nextExecution) revert NotEnoughTimePast();
        uint256 executionWindowEnded;
        unchecked {
            executionWindowEnded = nextExecution + _executionWindow;
        }
        if (block.timestamp >= executionWindowEnded) {
            revert JobExpired();
        }
        job.lastExecution = nextExecution;

        return (job.lastExecution);
    }

    /**
     * @notice Stores the parameters for a job in the params mapping.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _inputs The encoded parameters for the job.
     * @param _executionWindow The amount of time the job can be executed within.
     * @return initialExecution Whether the job should be executed immediately.
     */
    function onCreateJob(uint256 _index, bytes calldata _inputs, uint32 _executionWindow)
        external
        override
        onlyJobRegistry
        returns (bool initialExecution)
    {
        uint32 cooldown;
        uint40 initialExecutionTime;
        assembly {
            cooldown := calldataload(_inputs.offset)
            initialExecutionTime := calldataload(add(_inputs.offset, 0x20))
        }
        if (_executionWindow > cooldown) revert CooldownLessThanExecutionWindow();

        initialExecution = initialExecutionTime <= block.timestamp;
        if (initialExecution) {
            params[_index] = Params({lastExecution: uint40(block.timestamp), cooldown: cooldown});
        } else {
            params[_index] = Params({lastExecution: initialExecutionTime - cooldown, cooldown: cooldown});
        }
        return (initialExecution);
    }

    /**
     * @notice Deletes the parameters for a job in the params mapping.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice COmputes whether a job is expired.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _executionWindow The amount of time the job can be executed within.
     * @return isExpired Whether the job is expired.
     */
    function jobIsExpired(uint256 _index, uint32 _executionWindow) public view override returns (bool) {
        Params memory job = params[_index];
        unchecked {
            return uint256(job.lastExecution) + uint256(job.cooldown) + uint256(_executionWindow) <= block.timestamp;
        }
    }

    /**
     * @notice Computes whether a job is in execution mode.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _executionWindow The amount of time the job can be executed within.
     * @return isInExecutionMode Whether the job is in execution mode.
     */
    function jobIsInExecutionMode(uint256 _index, uint32 _executionWindow) public view override returns (bool) {
        Params memory job = params[_index];
        uint256 nextExecution;
        uint256 endTime;
        unchecked {
            // job.lastExecution + job.cooldown + _executionWindow will all fit in one uint256
            nextExecution = uint256(job.lastExecution) + uint256(job.cooldown);
            endTime = nextExecution + _executionWindow;
        }
        return block.timestamp >= nextExecution && block.timestamp < endTime;
    }

    /**
     * @notice Returns the encoded parameters for a job.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @return encodedData The encoded parameters for the job.
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(param.lastExecution, param.cooldown);
    }
}
