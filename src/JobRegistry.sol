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
 */

/// @notice JobRegistry keeps track of all jobs in the EES. It is through this contract jobs are created, managed and deleted.
contract JobRegistry is IJobRegistry, EIP712, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferFromNoRevert for ERC20;
    using JobSpecificationHash for JobSpecification;
    using FeeModuleInputHash for FeeModuleInput;

    Job[] public jobs;

    PublicERC6492Validator public immutable publicERC6492Validator;

    Coordinator internal immutable coordinator;

    // covering constant gas usage of execute which is not already measured in the function
    uint256 private constant _EXECUTION_GAS_OVERHEAD = 200_000;

    // for single use nonces
    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    constructor(Coordinator _coordinator, PublicERC6492Validator _publicERC6492Validator) {
        coordinator = _coordinator;
        publicERC6492Validator = _publicERC6492Validator;
    }

    /**
     * @notice Creates a job with given specification and stores it in the jobs array. It calls the callback funcitons onCreateJob on both the execution module and the application.
     * @notice The nonce and deadline fieds inside _specification are only considered if _sponsor is not zero address.
     * @param _specification Struct containing specifications of the job.
     * @param _sponsor The address paying execution fees related to the job. If zero address, msg.sender is set to sponsor and _sponsorSignature is not verified.
     * @param _sponsorSignature EIP-712 signature of _specification signed by _sponsor.
     * @param _index The index in the jobs array which the job should be created at. If this is greater than or equal to jobs.length then the array will be extended, otherwise it will try to reuse an index of an existing expired job.
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
     * @notice Executes a job, calling onExecuteJob on the execution module, fee module and application.
     * @notice The execution fee is taken from the sponsor. If the transfer fails and sponsorFallbackToOwner is true, the owner pays the fee.
     * @notice May deactivate the job if application reverted and ignoreAppRevert is false or maxExecutions is reached.
     * @param _index Index of the job in the jobs array.
     * @param _feeRecipient Address who receives execution fee tokens.
     * @return executionFee The execution fee taken.
     * @return executionFeeToken The ERC-20 token of the execution fee.
     * @return executionModule The execution module of the job.
     * @return feeModule The fee module of the job.
     * @return inZeroFeeWindow Whether the job was executed in the zero fee window.
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
     * @notice Deactivates a job preventing it from being executed.
     * @notice Deactivated jobs are still stored in the jobs array, but can be deleted by anyone after the job has expired.
     * @param _index Index of the job in the jobs array.
     */
    function deactivateJob(uint256 _index) public override {
        Job storage job = jobs[_index];
        if (msg.sender != job.owner) revert Unauthorized();
        job.active = false;
        emit JobDeactivated(_index, job.owner, address(job.application));
    }

    /**
     * @notice Activates a job, setting the active flag to true.
     * @param _index Index of the job in the jobs array.
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
     * @notice Deletes the job from the jobs array and calls onDeleteJob on execution module and application.
     * @notice Deleted jobs are removed from the jobs array.
     * @notice Can only be called by the owner of the job.
     * @param _index The index of the job in the jobs array.
     */
    function deleteJob(uint256 _index) public override nonReentrant {
        if (msg.sender != jobs[_index].owner) revert Unauthorized();
        _deleteJob(_index);
    }

    /**
     * @notice Revokes sponsorship of a job. This will make the owner the sponsor.
     * @notice Only callable by the sponsor or owner of the job.
     * @param _index Index of the job in the jobs array.
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
     * @notice Updates data in a fee module or migrates to other fee module.
     * @notice Removes current sponsorship from the job.
     * @notice If _sponsor is zero address, it will be set to job.owner.
     * @notice If job.sponsorCanUpdateFeeModule is true, both sponsor and owner can update fee module. The sponsor can even update the sponsor with a new signature.
     * @notice If job.sponsorCanUpdateFeeModule is false, only owner can update fee module.
     * @param _feeModuleInput Signable struct containing the index of the job and the data to be updated.
     * @param _sponsor The address paying execution fees related to the job.
     * @param _sponsorSignature EIP-712 signature of _feeModuleInput signed by _sponsor.
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
     * @notice Gets the length of the job array.
     * @return length The length of the job array.
     */
    function getJobsArrayLength() public view override returns (uint256 length) {
        return jobs.length;
    }

    /**
     * @notice Invalidate multiple unordered nonces for the caller.
     * @dev Allows the caller to batch invalidate nonces using a bitmask.
     *      This can be useful in scenarios where multiple nonces need to be invalidated at once,
     *      such as when several nonces are compromised or outdated.
     * @param _wordPos The position in the nonce bitmap (index of the word) where the nonces should be invalidated.
     * @param _mask A bitmask where each bit set to 1 invalidates the corresponding nonce in the bitmap.
     */
    function invalidateUnorderedNonces(uint256 _wordPos, uint256 _mask) external {
        nonceBitmap[msg.sender][_wordPos] |= _mask;
        emit UnorderedNonceInvalidation(msg.sender, _wordPos, _mask);
    }

    /**
     * @notice Returns the index of the bitmap and the bit position within the bitmap. Used for unordered nonces
     * @notice Taken from the PERMIT-2's SignatureTransfer contract https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol
     * @param _nonce The nonce to get the associated word and bit positions
     * @return wordPos The word position or index into the nonceBitmap
     * @return bitPos The bit position
     * @dev The first 248 bits of the nonce value is the index of the desired bitmap
     * @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
     */
    function bitmapPositions(uint256 _nonce) private pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(_nonce >> 8);
        bitPos = uint8(_nonce);
    }

    /**
     * @notice Deletes the job from the jobs array and calls onDeleteJob on execution module and application.
     * @param _index The index of the job in the jobs array.
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
     * @notice Checks whether a nonce is taken and sets the bit at the bit position in the bitmap at the word position
     * @notice Taken and modified from the PERMIT-2's SignatureTransfer contract https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol
     * @param _from The address to use the nonce at.
     * @param _nonce The nonce to spend.
     * @param _consume Flag which is true if the nonce should be consumed.
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
     * @dev This function encodes and returns key configuration parameters of the contract
     * @return config bytes array containing the encoded configuration data:
     *         - _EXECUTION_GAS_OVERHEAD: The constant gas overhead for job execution
     */
    function exportConfig() public view returns (bytes memory) {
        return abi.encode(_EXECUTION_GAS_OVERHEAD);
    }
}
