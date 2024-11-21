// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IApplication} from "./IApplication.sol";
import {IExecutionModule} from "./IExecutionModule.sol";
import {IFeeModule} from "./IFeeModule.sol";

interface IJobRegistry {
    struct Job {
        address owner;
        bool active;
        bool ignoreAppRevert;
        // having both sponsorFallbackToOwner and sponsorCanUpdateFeeModule is dangerous as sponsor can update fee module and revoke immediately
        bool sponsorFallbackToOwner;
        bool sponsorCanUpdateFeeModule;
        bytes1 executionModule;
        bytes1 feeModule;
        uint32 executionWindow;
        address sponsor;
        uint48 executionCounter;
        uint48 maxExecutions;
        IApplication application;
        // uint96 is sufficient to hold UNIX block.timestamp for practical future
        uint96 creationTime;
    }

    struct JobSpecification {
        uint256 nonce;
        uint256 deadline;
        bool reusableNonce;
        bool sponsorFallbackToOwner;
        bool sponsorCanUpdateFeeModule;
        IApplication application;
        uint32 executionWindow;
        uint48 maxExecutions;
        bool ignoreAppRevert;
        bytes1 executionModule;
        bytes1 feeModule;
        bytes executionModuleInput;
        bytes feeModuleInput;
        bytes applicationInput;
    }

    struct FeeModuleInput {
        uint256 nonce;
        uint256 deadline;
        bool reusableNonce;
        uint256 index;
        bytes1 feeModule;
        bytes feeModuleInput;
    }

    function createJob(
        JobSpecification calldata _specification,
        address _sponsor,
        bytes calldata _sponsorSignature,
        uint256 _index
    ) external returns (uint256 index);
    function execute(uint256 _index, address _feeRecipient) external returns (uint96, uint256, address, uint8, uint8);
    function deleteJob(uint256 _index) external;
    function deactivateJob(uint256 _index) external;
    function revokeSponsorship(uint256 _index) external;
    function updateFeeModule(
        FeeModuleInput calldata _feeModuleInput,
        address _sponsor,
        bytes calldata _sponsorSignature
    ) external;
    function getJobsArrayLength() external view returns (uint256);

    event JobCreated(uint256 indexed index, address indexed owner, address indexed application, bool initialExecution);
    event JobDeleted(
        uint256 indexed index, address indexed owner, address indexed application, bool applicationRevertedOnDelete
    );
    event JobDeactivated(uint256 indexed index, address indexed owner, address indexed application);
    event JobExecuted(
        uint256 indexed index,
        address indexed owner,
        address indexed application,
        bool success,
        uint48 executionNumber,
        uint256 executionFee,
        address executionFeeToken
    );
    event FeeModuleUpdate(uint256 indexed index, address indexed owner, address indexed sponsor);

    /// @notice Emits an event when the owner successfully invalidates an unordered nonce.
    event UnorderedNonceInvalidation(address indexed owner, uint256 word, uint256 mask);

    /// @notice Thrown when trying to look interact with a job that has been deleted
    error JobIsDeleted();

    /// @notice Thrown when a job aldready exists at index
    error JobAlreadyExistsAtIndex();

    /// @notice Thrown when the caller is not authorized
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

    /// @notice Thrown when the job is not active
    error JobNotActive();


    /// @notice Thrown when the job is not expired or is active
    error JobNotExpiredOrActive();

    /// @notice Thrown when at least one module is not valid
    error InvalidModule();

    /// @notice Thrown when the transfer of execution fee fails
    error TransferFailed();
}
