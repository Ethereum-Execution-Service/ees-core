// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IApplication {
    /// @dev Should most likely be restricted to only be called by the JobRegistry contract.
    /// @dev Called by JobRegistry contract upon execution of job with this application.
    /// @param _index The index of the job in the jobs array in the JobRegistry contract.
    /// @param _owner The owner of the job which is being executed.
    /// @param _executionNumber The execution number of the job which is being executed. Starts from 0.
    function onExecuteJob(uint256 _index, address _owner, uint48 _executionNumber) external;

    /// @dev Should most likely be restricted to only be called by the JobRegistry contract.
    /// @dev Suggestion: Check that the execution module is supported by the application. Some execution modules might not fit well with some applications.
    /// @dev _inputs can be decoded according to the application to extract necessary initialisation values.
    /// @dev Called by JobRegistry contract upon creation of a job with this application.
    /// @param _index The index of the job in the jobs array in the JobRegistry contract.
    /// @param _executionModule The execution module of the job which is being executed.
    /// @param _owner The owner of the job which is being executed.
    /// @param _inputs Bytes array containing arbitrary inputs.
    function onCreateJob(uint256 _index, bytes1 _executionModule, address _owner, bytes calldata _inputs) external;

    /// @dev Should most likely be restricted to only be called by the JobRegistry contract.
    /// @dev Called by JobRegistry contract upon deletion of a job with this application.
    /// @param _index The index of the job in the jobs array in the JobRegistry contract.
    /// @param _owner The owner of the job which is being executed.
    function onDeleteJob(uint256 _index, address _owner) external;
}
