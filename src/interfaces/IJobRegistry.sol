// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IApplication} from "./IApplication.sol";
import {IExecutionModule} from "./IExecutionModule.sol";
import {IFeeModule} from "./IFeeModule.sol";

interface IJobRegistry {
    struct Job {
        address owner;
        address sponsor;
        uint48 executionCounter;
        uint48 maxExecutions;
        IApplication application;
        bytes1 executionModule;
        bytes1 feeModule;
        uint32 executionWindow;
    }

    function createJob(
        JobSpecification calldata _specification,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bool _hasSponsorship,
        uint256 _index
    ) external returns (uint256 index);
    function execute(uint256 _index, address _feeRecipient, bytes calldata _verificationData)
        external
        returns (uint256 executionFee, address executionFeeToken);
    function deleteJob(uint256 _index) external;
    function revokeSponsorship(uint256 _index) external;
    function addExecutionModule(IExecutionModule _module) external;
    function addFeeModule(IFeeModule _module) external;
    function updateFeeModule(
        FeeModuleInput calldata _feeModuleInput,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bool _hasSponsorship
    ) external;
    function updateProtocolFeeRatio(uint8 _protocolFeeRatio) external;
    function withdrawProtocolFee(address _token, address _recipient) external;
    function getJobsArrayLength() external view returns (uint256);

    event JobCreated(uint256 indexed index, address indexed owner, address indexed application, bool initialExecution);
    event JobDeleted(uint256 indexed index, address indexed owner, address indexed application);
    event JobExecuted(
        uint256 indexed index,
        address indexed owner,
        address indexed application,
        uint48 executionNumber,
        uint256 executionFee,
        address executionFeeToken
    );
    event FeeModuleUpdate(uint256 indexed index, address indexed owner, address indexed sponsor);
    event ApplicationRevertedUponJobDeletion(
        uint256 indexed index, address indexed owner, address application, bytes revertData
    );

    /// @notice Emits an event when the owner successfully invalidates an unordered nonce.
    event UnorderedNonceInvalidation(address indexed owner, uint256 word, uint256 mask);

    /// @notice Thrown when trying to look interact with a job that has been deleted
    error JobIsDeleted();

    /// @notice Thrown when a job aldready exists at index
    error JobAlreadyExistsAtIndex();

    /// @notice Thrown when the caller is not authorized to the action on the job
    error Unauthorized();

    /// @notice Thrown when the execution module is not supported
    error UnsupportedExecutionModule();

    /// @notice Thrown when the caller is not the executable
    error NotExecutable();

    /// @notice Thrown when the job is in execution mode
    error JobInExecutionMode();

    /// @notice Thrown when the fee calculated by the module exceeds the maximum fee
    error MaxExecutionFeeExceeded();

    /// @notice Thrown when maximum number of executions is exceeded.
    error MaxExecutionsExceeded();

    struct JobSpecification {
        uint256 nonce;
        uint256 deadline;
        IApplication application;
        uint32 executionWindow;
        uint48 maxExecutions;
        bytes1 executionModule;
        bytes1 feeModule;
        bytes executionModuleInput;
        bytes feeModuleInput;
        bytes applicationInput;
    }

    struct FeeModuleInput {
        uint256 nonce;
        uint256 deadline;
        uint256 index;
        bytes1 feeModule;
        bytes feeModuleInput;
    }
}
