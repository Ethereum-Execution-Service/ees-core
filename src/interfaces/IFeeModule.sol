// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeModule {
    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Called by JobRegistry contract upon execution of a job with this executable.
     * @dev _caller can be used to restrict who can call this function. This enables restriction of custom contracts to call execute in JobExpiry.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _caller The address of the caller of JobRegistry's execute function.
     * @param _executionWindow The time in seconds where the job can be executed within before expiring.
     * @param _executionTime The time when the job can be executed from.
     * @param _variableGasConsumption The gas consumed by the execution module and application during execution.
     * @return _executionFee The execution fee to be paid by the sponsor.
     * @return _executionFeeToken The token in which the fee is paid.
     */
    function onExecuteJob(
        uint256 _index,
        address _caller,
        uint32 _executionWindow,
        uint256 _executionTime,
        uint256 _variableGasConsumption
    ) external returns (uint256, address);

    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Called by JobRegistry contract upon creation of a job with this executable.
     * @dev _inputs can be decoded according to the module to extract necessary initialisation values.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _inputs Bytes array containing arbitrary inputs.
     */
    function onCreateJob(uint256 _index, bytes calldata _inputs) external;

    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @dev Should never revert except if caller is not JobRegistry.
     * @dev Called by JobRegistry contract upon deletion of a job with this executable.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     */
    function onDeleteJob(uint256 _index) external;

    /**
     * @dev Should be restricted to only be called by the JobRegistry contract.
     * @param _index The index of the job in the jobs array in the JobRegistry contract.
     * @param _inputs Bytes array containing arbitrary inputs.
     */
    function onUpdateData(uint256 _index, bytes calldata _inputs) external;

    /**
     * @notice Returns stored data encoded as a bytes array.
     */
    function getEncodedData(uint256 _index) external view returns (bytes memory);
}
