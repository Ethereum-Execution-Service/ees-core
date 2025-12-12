// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IApplication} from "./interfaces/IApplication.sol";
import {JobSpecificationHash} from "./libraries/JobSpecificationHash.sol";
import {FeeModuleInputHash} from "./libraries/FeeModuleInputHash.sol";
import {EIP712} from "./EIP712.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Coordinator} from "./Coordinator.sol";
import {SafeTransferFromNoRevert} from "./libraries/SafeTransferFromNoRevert.sol";
import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";

/**
 * __/\\\\\\\\\\\\\\\__/\\\\\\\\\\\\\\\_____/\\\\\\\\\\\___
 *  _\/\\\///////////__\/\\\///////////____/\\\/////////\\\_
 *   _\/\\\_____________\/\\\______________\//\\\______\///__
 *    _\/\\\\\\\\\\\_____\/\\\\\\\\\\\_______\////\\\_________
 *     _\/\\\///////______\/\\\///////___________\////\\\______
 *      _\/\\\_____________\/\\\_____________________\////\\\___
 *       _\/\\\_____________\/\\\______________/\\\______\//\\\__
 *        _\/\\\\\\\\\\\\\\\_\/\\\\\\\\\\\\\\\_\///\\\\\\\\\\\/___
 *         _\///////////////__\///////////////____\///////////_____
 *
 * @title JobRegistry
 * @notice Manages job lifecycle including creation, execution, and deletion
 * @dev Inherits from EIP712 for signature verification and ReentrancyGuard for reentrancy protection.
 *      Jobs are stored in an array and can be reused at expired indices. Supports sponsored jobs with
 *      EIP-712 signatures and ERC-6492 contract signatures.
 */
contract JobRegistry is IJobRegistry, EIP712, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferFromNoRevert for ERC20;
    using JobSpecificationHash for JobSpecification;
    using FeeModuleInputHash for FeeModuleInput;

    /// @notice Array of all jobs stored in the registry
    Job[] public jobs;

    /// @notice Validator for ERC-6492 signatures (allows contract signatures)
    PublicERC6492Validator public immutable publicERC6492Validator;

    /// @notice Coordinator contract that manages executors and modules
    Coordinator internal immutable coordinator;

    /// @notice Constant gas overhead for job execution
    /// @dev Covers gas usage not already measured in the execute function
    uint256 private constant _EXECUTION_GAS_OVERHEAD = 200_000;

    /// @notice Nonce bitmap for tracking used unordered nonces
    /// @dev Maps address => word position => bitmap. Used to prevent signature replay attacks.
    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    /**
     * @notice Initializes the JobRegistry contract
     * @param _coordinator Coordinator contract address
     * @param _publicERC6492Validator ERC-6492 signature validator address
     */
    constructor(Coordinator _coordinator, PublicERC6492Validator _publicERC6492Validator) {
        coordinator = _coordinator;
        publicERC6492Validator = _publicERC6492Validator;
    }

    /**
     * @notice Creates a new job with the given specification
     * @dev Validates signatures, calls module and application callbacks, and stores the job.
     *      Can reuse expired job indices. Supports sponsored jobs with separate signatures.
     * @param _specification Job specification containing all job parameters
     * @param _sponsor Address paying execution fees (zero address means msg.sender is sponsor)
     * @param _sponsorSignature EIP-712 signature of job specification signed by sponsor (if _sponsor != address(0))
     * @param _ownerSignature EIP-712 signature of job specification signed by owner (if msg.sender != owner)
     * @param _index Desired index in jobs array (UINT256_MAX to append, or existing index to reuse)
     * @return index The index where the job was created
     * @custom:emits JobCreated event with job index, creator, application, and initial execution status
     * @custom:emits JobExecuted event if initial execution occurs
     */
    function createJob(
        JobSpecification calldata _specification,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bytes calldata _ownerSignature,
        uint256 _index
    ) public override nonReentrant returns (uint256 index) {
        // *** SIGNATURE CHECKS ***
        bool hasSponsorship = _sponsor != address(0);
        bool callerIsOwner = msg.sender == _specification.owner;
        // signature expired, short circuit if no sponsorship or caller is owner
        if ((hasSponsorship || !callerIsOwner) && block.timestamp > _specification.deadline) {
            revert SignatureExpired(_specification.deadline);
        }
        if (hasSponsorship) {
            // do not consume nonce if it is reusable, but still check and revert if it has already been used
            _useUnorderedNonce(_sponsor, _specification.nonce, !_specification.reusableNonce);
            // do not include owner in the hash - allows sponsor to sign for any owner
            if (!publicERC6492Validator.isValidSignatureNowAllowSideEffects(
                    _sponsor, _hashTypedData(_specification.hashNoOwner()), _sponsorSignature
                )) revert InvalidSignature();
        }
        if (!callerIsOwner) {
            // always consume owner nonce and revert if it has already been used
            _useUnorderedNonce(_specification.owner, _specification.nonce, true);
            // include whole job specification in the hash
            if (!publicERC6492Validator.isValidSignatureNowAllowSideEffects(
                    _specification.owner, _hashTypedData(_specification.hash()), _ownerSignature
                )) revert InvalidSignature();
        }

        // *** MAX EXECUTIONS CHECK ***
        if (_specification.maxExecutions == 0) revert MaxExecutionsReached();

        // *** SETTING INDEX ***
        // attempts to reuse index of existing expired job if _index is existing. Otherwise creates new job at jobs.length.
        bool reuseIndex;
        if (_index < jobs.length) {
            (address executionModuleExistingJob,) = coordinator.modules(uint8(jobs[_index].executionModule));
            if (jobs[_index].owner == address(0)) {
                // existing job is already deleted - reuse it
                reuseIndex = true;
            } else if (IExecutionModule(executionModuleExistingJob).jobIsExpired(_index, jobs[_index].executionWindow))
            {
                // existing job is expired - reuse it but delete existing job first
                _deleteJob(_index);
                reuseIndex = true;
            }
        }
        index = reuseIndex ? _index : jobs.length;

        // *** MODULE FETCHING AND VALIDATION ***
        (address executionModuleAddress, bool isExecutionModule) =
            coordinator.modules(uint8(_specification.executionModule));
        IExecutionModule executionModule = IExecutionModule(executionModuleAddress);
        (address feeModuleAddress, bool isNotFeeModule) = coordinator.modules(uint8(_specification.feeModule));
        IFeeModule feeModule = IFeeModule(feeModuleAddress);
        // revert if intended execution module is not registered as execution module or fee module intended is not registered as a fee module
        if (!isExecutionModule || isNotFeeModule) revert InvalidModule();

        // *** MODULE AND APPLICATION CALLS ***
        bool initialExecution =
            executionModule.onCreateJob(index, _specification.executionModuleInput, _specification.executionWindow);
        feeModule.onCreateJob(index, _specification.feeModuleInput);

        _specification.application
            .onCreateJob(
                index,
                msg.sender,
                _specification.ignoreAppRevert,
                _specification.executionWindow,
                _specification.executionModule,
                _specification.executionModuleInput,
                _specification.applicationInput
            );
        bool active = true;

        // *** HANDLING INITIAL EXECUTION ***
        if (initialExecution) {
            // executes application, reverts whole call if it fails
            _specification.application.onExecuteJob(index, msg.sender, 0);
            emit JobExecuted(index, msg.sender, address(_specification.application), true, 0, 0, address(0), false);
            // deactivate job immediately if maxExecutions is 1
            if (_specification.maxExecutions == 1) active = false;
        }

        // *** STORING JOB ***
        Job memory newJob = Job({
            owner: msg.sender,
            active: active,
            ignoreAppRevert: _specification.ignoreAppRevert,
            sponsorFallbackToOwner: _specification.sponsorFallbackToOwner,
            sponsorCanUpdateFeeModule: _specification.sponsorCanUpdateFeeModule,
            executionModule: _specification.executionModule,
            feeModule: _specification.feeModule,
            executionWindow: _specification.executionWindow,
            zeroFeeWindow: _specification.zeroFeeWindow,
            sponsor: hasSponsorship ? _sponsor : msg.sender,
            executionCounter: initialExecution ? 1 : 0,
            maxExecutions: _specification.maxExecutions,
            application: _specification.application,
            creationTime: uint96(block.timestamp)
        });
        if (reuseIndex) {
            jobs[index] = newJob;
        } else {
            jobs.push(newJob);
        }

        emit JobCreated(index, msg.sender, address(_specification.application), initialExecution);
        return index;
    }

    /**
     * @notice Executes a job by calling execution module, fee module, and application
     * @dev Can only be called by the Coordinator. Execution fee is collected from sponsor (or owner if fallback enabled).
     *      Job may be deactivated if application reverts (and ignoreAppRevert is false) or maxExecutions is reached.
     * @param _index Index of the job in the jobs array
     * @param _feeRecipient Address to receive the execution fee tokens
     * @return executionFee Amount of execution fee collected
     * @return executionFeeToken ERC20 token address of the execution fee
     * @return executionModule Execution module ID used by the job
     * @return feeModule Fee module ID used by the job
     * @return inZeroFeeWindow Whether the job was executed within the zero fee window
     * @custom:emits JobExecuted event with execution details
     */
    function execute(uint256 _index, address _feeRecipient)
        external
        override
        nonReentrant
        returns (
            uint256 executionFee,
            address executionFeeToken,
            uint8 executionModule,
            uint8 feeModule,
            bool inZeroFeeWindow
        )
    {
        // *** CHECKS ***
        if (msg.sender != address(coordinator)) revert Unauthorized();
        Job memory job = jobs[_index];

        // job.owner can only be 0 if job was deleted or was never created
        if (job.owner == address(0)) revert JobIsDeleted();
        // job must be active to be executed
        if (!job.active) revert JobNotActive();

        // *** MODULE FETCHING ***
        // assumes jobs are created with modules that are correctly registered in coordinator
        (address executionModuleAddress,) = coordinator.modules(uint8(job.executionModule));
        //IExecutionModule executionModuleContract = IExecutionModule(executionModuleAddress);
        (address feeModuleAddress,) = coordinator.modules(uint8(job.feeModule));
        //IFeeModule feeModuleContract = IFeeModule(feeModuleAddress);

        // *** EXECUTION MODULE CALL ***
        // pass gas consumption to fee module
        uint256 startVariableGas = gasleft();
        // timestamp when the job was executable, used in fee module
        // execution module should revert if job is expired or not executable at the time of execution
        uint256 executionTime = IExecutionModule(executionModuleAddress).onExecuteJob(_index, job.executionWindow);
        // it is applications reponsibility that this doesnt revert. Sponsor pays fee either way
        bool success;
        try job.application.onExecuteJob(_index, job.owner, job.executionCounter) {
            success = true;
        } catch {}
        bool maxExecutionsReached;
        if (success) {
            // only increment if successfully executed
            maxExecutionsReached = ++jobs[_index].executionCounter == job.maxExecutions;
        }
        if ((!success && !job.ignoreAppRevert) || maxExecutionsReached) {
            // inactivate job if application reverted without ignoreAppRevert or maxExecutions reached
            jobs[_index].active = false;
        }

        // *** GAS USAGE ANDFEE MODULE CALL ***
        uint256 totalGas;
        unchecked {
            // startVariableGas < gasleft() and shouldnt overflow uint256 with _EXECUTION_GAS_OVERHEAD
            totalGas = _EXECUTION_GAS_OVERHEAD + startVariableGas - gasleft();
        }
        // fee module monitors its own gas usage
        (executionFee, executionFeeToken, inZeroFeeWindow) = IFeeModule(feeModuleAddress)
            .onExecuteJob(_index, job.executionWindow, job.zeroFeeWindow, executionTime, totalGas);

        // *** FEE TRANSFER ***
        if (executionFee > 0) {
            // try to transfer from sponsor first, if that fails and sponsorFallbackToOwner is true, transfer from owner and set sponsor to owner
            if (!ERC20(executionFeeToken).safeTransferFromNoRevert(job.sponsor, _feeRecipient, executionFee)) {
                if (job.sponsorFallbackToOwner) {
                    ERC20(executionFeeToken).safeTransferFrom(job.owner, _feeRecipient, executionFee);
                    jobs[_index].sponsor = job.owner;
                } else {
                    revert TransferFailed();
                }
            }
        }
        emit JobExecuted(
            _index,
            job.owner,
            address(job.application),
            success,
            success ? job.executionCounter + 1 : job.executionCounter,
            executionFee,
            executionFeeToken,
            inZeroFeeWindow
        );
        return (executionFee, executionFeeToken, uint8(job.executionModule), uint8(job.feeModule), inZeroFeeWindow);
    }

    /**
     * @notice Deactivates a job, preventing it from being executed
     * @dev Can only be called by the job owner. Deactivated jobs remain in the array but cannot be executed.
     *      Expired deactivated jobs can be deleted by anyone.
     * @param _index Index of the job in the jobs array
     * @custom:emits JobDeactivated event with job index, owner, and application address
     */
    function deactivateJob(uint256 _index) public override {
        Job storage job = jobs[_index];
        if (msg.sender != job.owner) revert Unauthorized();
        job.active = false;
        emit JobDeactivated(_index, job.owner, address(job.application));
    }

    /**
     * @notice Activates a previously deactivated job
     * @dev Can only be called by the job owner. Cannot activate if maxExecutions has been reached.
     * @param _index Index of the job in the jobs array
     * @custom:emits JobActivated event with job index, owner, and application address
     */
    function activateJob(uint256 _index) public override {
        Job storage job = jobs[_index];
        if (msg.sender != job.owner) revert Unauthorized();
        // prevent reactivation if maxExecutions is reached
        if (job.executionCounter >= job.maxExecutions) revert MaxExecutionsReached();
        job.active = true;
        emit JobActivated(_index, job.owner, address(job.application));
    }

    /**
     * @notice Deletes a job from the jobs array
     * @dev Can only be called by the job owner. Calls onDeleteJob on execution module, fee module, and application.
     *      Application callback failures are caught and logged but don't prevent deletion.
     * @param _index Index of the job in the jobs array
     * @custom:emits JobDeleted event with job index, owner, application, and whether application callback reverted
     */
    function deleteJob(uint256 _index) public override nonReentrant {
        if (msg.sender != jobs[_index].owner) revert Unauthorized();
        _deleteJob(_index);
    }

    /**
     * @notice Revokes sponsorship of a job, making the owner the new sponsor
     * @dev Can be called by either the current sponsor or the job owner. If sponsor calls and
     *      sponsorFallbackToOwner is false, sponsor is set to address(0).
     * @param _index Index of the job in the jobs array
     * @custom:emits SponsorshipRevoked event with job index, owner, new sponsor, and old sponsor
     */
    function revokeSponsorship(uint256 _index) public override {
        Job storage job = jobs[_index];
        address oldSponsor = job.sponsor;
        address newSponsor = job.owner;
        if (msg.sender == oldSponsor) {
            if (job.sponsorFallbackToOwner) {
                job.sponsor = job.owner;
            } else {
                job.sponsor = address(0);
                newSponsor = address(0);
            }
        } else if (msg.sender == job.owner) {
            job.sponsor = job.owner;
        } else {
            revert Unauthorized();
        }
        emit SponsorshipRevoked(_index, job.owner, newSponsor, oldSponsor);
    }

    /**
     * @notice Updates fee module data or migrates to a different fee module
     * @dev Removes current sponsorship. If sponsorCanUpdateFeeModule is true, both sponsor and owner can update.
     *      Cannot be called when job is in execution mode. Supports fee module migration.
     * @param _feeModuleInput Signable struct containing job index, fee module ID, and update data
     * @param _sponsor New sponsor address (zero address means owner becomes sponsor)
     * @param _sponsorSignature EIP-712 signature of _feeModuleInput signed by _sponsor (if _sponsor != address(0))
     * @custom:emits FeeModuleUpdate event with job index, owner, sponsor, and fee module ID
     */
    function updateFeeModule(
        FeeModuleInput calldata _feeModuleInput,
        address _sponsor,
        bytes calldata _sponsorSignature
    ) public override nonReentrant {
        Job storage job = jobs[_feeModuleInput.index];
        bool currentSponsorUpdating = job.sponsorCanUpdateFeeModule && msg.sender == job.sponsor;

        // *** CHECKS ***
        // if job.sponsorCanUpdateFeeModule both sponsor and owner can update fee module
        // if !job.sponsorCanUpdateFeeModule only owner can update fee module
        if (msg.sender != job.owner && !currentSponsorUpdating) {
            revert Unauthorized();
        }
        // Check that job is not in execution mode
        (address executionModuleAddress,) = coordinator.modules(uint8(job.executionModule));
        if (IExecutionModule(executionModuleAddress).jobIsInExecutionMode(_feeModuleInput.index, job.executionWindow)) {
            revert JobInExecutionMode();
        }

        // *** SPONSORSHIP AND SIGNATURE CHECKS ***
        bool newSponsorShip = _sponsor != address(0);
        if (newSponsorShip) {
            if (block.timestamp > _feeModuleInput.deadline) revert SignatureExpired(_feeModuleInput.deadline);
            _useUnorderedNonce(_sponsor, _feeModuleInput.nonce, !_feeModuleInput.reusableNonce);
            if (!publicERC6492Validator.isValidSignatureNowAllowSideEffects(
                    _sponsor, _hashTypedData(_feeModuleInput.hash()), _sponsorSignature
                )) revert InvalidSignature();
            job.sponsor = _sponsor;
        } else if (!currentSponsorUpdating) {
            job.sponsor = job.owner;
        }

        // *** FEE MODULE UPDATE OR MIGRATION ***
        (address currentFeeModuleAddress,) = coordinator.modules(uint8(job.feeModule));
        IFeeModule currentFeeModule = IFeeModule(currentFeeModuleAddress);
        if (_feeModuleInput.feeModule == job.feeModule) {
            // Update existing fee module with new data
            currentFeeModule.onUpdateData(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor, _feeModuleInput.feeModule);
        } else {
            // Migrate to new fee module
            (address newFeeModuleAddress, bool isNotFeeModule) = coordinator.modules(uint8(_feeModuleInput.feeModule));
            if (isNotFeeModule) revert InvalidModule();
            IFeeModule newFeeModule = IFeeModule(newFeeModuleAddress);
            currentFeeModule.onDeleteJob(_feeModuleInput.index);
            newFeeModule.onCreateJob(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            job.feeModule = _feeModuleInput.feeModule;
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor, _feeModuleInput.feeModule);
        }
    }

    /**
     * @notice Returns the total number of jobs in the registry
     * @dev Includes both active and deleted jobs. Deleted jobs have owner == address(0).
     * @return length Total number of jobs in the jobs array
     */
    function getJobsArrayLength() public view override returns (uint256 length) {
        return jobs.length;
    }

    /**
     * @notice Invalidates multiple unordered nonces for the caller using a bitmask
     * @dev Useful for batch invalidating nonces when they are compromised or outdated.
     *      Each bit set to 1 in _mask invalidates the corresponding nonce.
     * @param _wordPos Word position (index) in the nonce bitmap
     * @param _mask Bitmask where each set bit invalidates the corresponding nonce
     * @custom:emits UnorderedNonceInvalidation event with caller, word position, and mask
     */
    function invalidateUnorderedNonces(uint256 _wordPos, uint256 _mask) external {
        nonceBitmap[msg.sender][_wordPos] |= _mask;
        emit UnorderedNonceInvalidation(msg.sender, _wordPos, _mask);
    }

    /**
     * @notice Calculates the bitmap word position and bit position for a given nonce
     * @dev Implementation from PERMIT-2's SignatureTransfer contract.
     *      First 248 bits = word position, last 8 bits = bit position.
     * @param _nonce The nonce to calculate positions for
     * @return wordPos Word position (index) in the nonce bitmap
     * @return bitPos Bit position within the word
     */
    function bitmapPositions(uint256 _nonce) private pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(_nonce >> 8);
        bitPos = uint8(_nonce);
    }

    /**
     * @notice Deletes a job and calls cleanup callbacks on modules and application
     * @dev Internal function that handles job deletion logic. Application callback failures are caught.
     * @param _index Index of the job to delete
     * @custom:emits JobDeleted event with job details and whether application callback reverted
     */
    function _deleteJob(uint256 _index) private {
        Job memory job = jobs[_index];

        (address executionModuleAddress,) = coordinator.modules(uint8(job.executionModule));
        IExecutionModule executionModule = IExecutionModule(executionModuleAddress);
        (address feeModuleAddress,) = coordinator.modules(uint8(job.feeModule));
        IFeeModule feeModule = IFeeModule(feeModuleAddress);

        delete jobs[_index];

        // these should never revert, the owner should always be able to delete a job
        executionModule.onDeleteJob(_index);
        feeModule.onDeleteJob(_index);

        bool revertOnDelete;
        try job.application.onDeleteJob(_index, job.owner) {}
        catch {
            revertOnDelete = true;
        }
        emit JobDeleted(_index, job.owner, address(job.application), revertOnDelete);
    }

    /**
     * @notice Checks if a nonce is used and optionally consumes it
     * @dev Implementation from PERMIT-2's SignatureTransfer contract (modified).
     *      If _consume is true, marks nonce as used. If false, only checks if already used.
     * @param _from Address whose nonce is being checked
     * @param _nonce Nonce to check/consume
     * @param _consume If true, consume the nonce; if false, only check if used
     */
    function _useUnorderedNonce(address _from, uint256 _nonce, bool _consume) internal {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(_nonce);
        uint256 bit = 1 << bitPos;

        if (_consume) {
            // check and update map
            uint256 flipped = nonceBitmap[_from][wordPos] ^= bit;
            if (flipped & bit == 0) revert InvalidNonce();
        } else {
            // dont update map, just check if nonce is used
            if (nonceBitmap[_from][wordPos] & bit != 0) revert InvalidNonce();
        }
    }

    /**
     * @notice Exports the configuration of the JobRegistry contract
     * @dev Returns encoded configuration data for off-chain tools and verification
     * @return config Encoded bytes containing the execution gas overhead constant
     */
    function exportConfig() public view returns (bytes memory) {
        return abi.encode(_EXECUTION_GAS_OVERHEAD);
    }
}
