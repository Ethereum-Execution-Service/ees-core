// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRegularTimeInterval} from "../interfaces/executionModules/IRegularTimeInterval.sol";
import {Coordinator} from "../Coordinator.sol";

/**
 * @title RegularTimeInterval
 * @notice Execution module that enforces regular time intervals between job executions
 * @dev Jobs using this module can only be executed after a cooldown period has elapsed since
 *      the last execution. The cooldown and initial execution time are configurable per job.
 */
contract RegularTimeInterval is IRegularTimeInterval {
    /// @notice The Coordinator contract that manages this execution module
    Coordinator public immutable coordinator;

    /// @notice Mapping from job index to execution parameters (lastExecution timestamp and cooldown period)
    mapping(uint256 => Params) public params;

    /**
     * @notice Initializes the RegularTimeInterval execution module
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
     * @notice Computes the next execution time for a job and updates the last execution timestamp
     * @dev Verifies that enough time has passed since the last execution (cooldown period)
     *      and that the execution window hasn't expired. Updates lastExecution to the computed
     *      execution time if valid.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _executionWindow The amount of time the job can be executed within (in seconds)
     * @return executionTime The timestamp from which the job can be executed
     * @custom:reverts NotEnoughTimePast if cooldown period hasn't elapsed
     * @custom:reverts JobExpired if the execution window has already passed
     */
    function onExecuteJob(uint256 _index, uint32 _executionWindow)
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
     * @notice Stores the parameters for a job when it is created
     * @dev Decodes the input bytes to extract cooldown and initialExecutionTime.
     *      If initialExecutionTime is in the past, sets lastExecution to current timestamp.
     *      Otherwise, sets lastExecution to initialExecutionTime - cooldown to ensure
     *      the first execution happens at initialExecutionTime.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _inputs Encoded parameters: cooldown (uint32) and initialExecutionTime (uint40)
     * @param _executionWindow The amount of time the job can be executed within (in seconds)
     * @return initialExecution Whether the job should be executed immediately (true if initialExecutionTime <= now)
     * @custom:reverts CooldownLessThanExecutionWindow if cooldown is less than executionWindow
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
     * @notice Deletes the parameters for a job when it is deleted
     * @param _index The index of the job in the jobs array in JobRegistry contract
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice Checks whether a job has expired (execution window has passed)
     * @dev A job is expired if: lastExecution + cooldown + executionWindow <= block.timestamp
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _executionWindow The amount of time the job can be executed within (in seconds)
     * @return isExpired True if the job's execution window has passed
     */
    function jobIsExpired(uint256 _index, uint32 _executionWindow) public view override returns (bool) {
        Params memory job = params[_index];
        unchecked {
            return uint256(job.lastExecution) + uint256(job.cooldown) + uint256(_executionWindow) <= block.timestamp;
        }
    }

    /**
     * @notice Checks whether a job is currently within its execution window
     * @dev A job is in execution mode if: nextExecution <= block.timestamp < nextExecution + executionWindow
     *      where nextExecution = lastExecution + cooldown
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _executionWindow The amount of time the job can be executed within (in seconds)
     * @return isInExecutionMode True if the job is currently within its execution window
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
     * @notice Returns the encoded parameters for a job
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @return encodedData ABI-encoded parameters: (lastExecution, cooldown)
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(param.lastExecution, param.cooldown);
    }
}
