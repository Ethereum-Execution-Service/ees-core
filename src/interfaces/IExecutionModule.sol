// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExecutionModule {
    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Called by JobRegistry contract upon execution of a job with this executable.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _executionWindow The time in seconds where the job can be executed within before expiring.
     * @param _verificationData Arbitrary data to be verified by the module.
     * @return executionTime The time from which the job can be executed.
     */
    function onExecuteJob(uint256 _index, uint32 _executionWindow, bytes calldata _verificationData)
        external
        returns (uint256);

    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Called by JobRegistry contract upon creation of a job with this executable.
     * @dev _inputs can be decoded according to the module to extract necessary initialisation values.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _inputs Bytes array containing arbitrary inputs.
     * @param _executionWindow The time in seconds where the job can be executed within before expiring.
     * @return _initialExecution A flag whether the job should be executed immediately upon creation.
     */
    function onCreateJob(uint256 _index, bytes calldata _inputs, uint32 _executionWindow) external returns (bool);

    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Should never revert except if caller is not JobRegistry.
     * @dev Called by JobRegistry contract upon deletion of a job with this executable.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     */
    function onDeleteJob(uint256 _index) external;

    /**
     * @dev Used by JobRegistry to check if a job is expired or not. If true, the job might get deleted.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _executionWindow The time in seconds where the job can be executed within before expiring.
     * @return _isExpired Whether the job is expired or not.
     */
    function jobIsExpired(uint256 _index, uint32 _executionWindow) external view returns (bool);

    /**
     * @dev Used by off-chain executors to check if a job is executable or not.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _executionWindow The time in seconds where the job can be executed within before expiring.
     * @return _isInExecutionMode Whether the job is in execution mode (able to be executed) or not.
     */
    function jobIsInExecutionMode(uint256 _index, uint32 _executionWindow) external view returns (bool);

    /**
     * @notice Returns stored data encoded as a bytes array.
     */
    function getEncodedData(uint256 _index) external view returns (bytes memory);
}
