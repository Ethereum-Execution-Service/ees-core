// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {IApplication} from "./interfaces/IApplication.sol";
import {JobSpecificationHash} from "./libraries/JobSpecificationHash.sol";
import {FeeModuleInputHash} from "./libraries/FeeModuleInputHash.sol";
import {EIP712} from "./EIP712.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {Coordinator} from "./Coordinator.sol";
import {SafeTransferFromNoRevert} from "./libraries/SafeTransferFromNoRevert.sol";
import {PublicERC6492Validator} from "./PublicERC6492Validator.sol";
import {ReentrancyGuard} from "solmate/src/utils/ReentrancyGuard.sol";

/// @author Victor Brevig
/// @notice JobRegistry keeps track of all jobs in the EES. It is through this contract jobs are created, managed and deleted.
contract JobRegistry is IJobRegistry, EIP712, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferFromNoRevert for ERC20;
    using JobSpecificationHash for JobSpecification;
    using FeeModuleInputHash for FeeModuleInput;

    PublicERC6492Validator public immutable publicERC6492Validator;

    Job[] public jobs;

    Coordinator internal immutable coordinator;

    // covering constant gas usage of execute which is not already measured in the function
    uint256 private constant _EXECUTION_GAS_OVERHEAD = 200000;

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
        // SIGNATURE CHECKS
        bool hasSponsorship = _sponsor != address(0);
        bool callerIsOwner = msg.sender == _specification.owner;
        if((hasSponsorship || !callerIsOwner) && block.timestamp > _specification.deadline) {
            revert SignatureExpired(_specification.deadline);
        }
        if (hasSponsorship) {
            // do not consume nonce if it is reusable, but still check if it is used
            _useUnorderedNonce(_sponsor, _specification.nonce, !_specification.reusableNonce);
            // we do not include owner in the hash, since the sponsor can sign for any owner
            if(!publicERC6492Validator.isValidSignatureNowAllowSideEffects(_sponsor, _hashTypedData(_specification.hashNoOwner()), _sponsorSignature)) revert InvalidSignature();
        }
        if(!callerIsOwner) {
            // always consume owner nonce
            _useUnorderedNonce(_specification.owner, _specification.nonce, true);
            if(!publicERC6492Validator.isValidSignatureNowAllowSideEffects(_specification.owner, _hashTypedData(_specification.hash()), _ownerSignature)) revert InvalidSignature();
        }

        // attempts to reuse index of existing expired job if _index is existing. Otherwise creates new job at jobs.length.
        bool reuseIndex = false;
        if(_index < jobs.length) {
            (address executionModuleExistingJob,) = coordinator.modules(uint8(jobs[_index].executionModule));
            if(jobs[_index].owner == address(0)) {
                // existingjob is already deleted, we can reuse it
                reuseIndex = true;
            } else if(IExecutionModule(executionModuleExistingJob).jobIsExpired(_index, jobs[_index].executionWindow)) {
                // existing job is expired, we can reuse it but have to delete existing job first
                _deleteJob(_index);
                reuseIndex = true;
            }
        }
        index = reuseIndex ? _index : jobs.length;

        (address executionModuleAddress, bool isExecutionModule) = coordinator.modules(uint8(_specification.executionModule));
        IExecutionModule executionModule = IExecutionModule(executionModuleAddress);
        (address feeModuleAddress, bool isNotFeeModule) = coordinator.modules(uint8(_specification.feeModule));
        IFeeModule feeModule = IFeeModule(feeModuleAddress);

        if(!isExecutionModule || isNotFeeModule) revert InvalidModule();

        bool initialExecution =
            executionModule.onCreateJob(index, _specification.executionModuleInput, _specification.executionWindow);
        feeModule.onCreateJob(index, _specification.feeModuleInput);

        _specification.application.onCreateJob(
            index, _specification.executionModule, msg.sender, _specification.applicationInput
        );
        bool active = true;
        if (initialExecution) {
            _specification.application.onExecuteJob(index, msg.sender, 0);
            emit JobExecuted(index, msg.sender, address(_specification.application), true, 0, 0, address(0), false);
            // can have initial execution and maxExecution = 1, then we just deactivate immediately
            if (_specification.maxExecutions == 1) active = false;
        }

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

        // fix index here!
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
     * @param _index Index of the job in the jobs array.
     * @param _feeRecipient Address who receives execution fee tokens.
     */
    function execute(uint256 _index, address _feeRecipient) external override nonReentrant returns (uint96, uint256, address, uint8, uint8, bool) {
        if (msg.sender != address(coordinator)) revert Unauthorized();
        Job memory job = jobs[_index];

        // job.owner can only be 0 if job was deleted
        if (job.owner == address(0)) revert JobIsDeleted();
        if (!job.active) revert JobNotActive();

        // assumes jobs are created with modules that are correctly registered in coordinator
        (address executionModuleAddress,) = coordinator.modules(uint8(job.executionModule));
        IExecutionModule executionModule = IExecutionModule(executionModuleAddress);
        (address feeModuleAddress,) = coordinator.modules(uint8(job.feeModule));
        IFeeModule feeModule = IFeeModule(feeModuleAddress);
        

        uint256 startVariableGas = gasleft();
        uint256 executionTime = executionModule.onExecuteJob(_index, job.executionWindow);

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
            // inactivate job
            jobs[_index].active = false;
        }

        uint256 totalGas;
        unchecked {
            // startVariableGas < gasleft() and shouldnt overflow uint256 with _EXECUTION_GAS_OVERHEAD
            totalGas = _EXECUTION_GAS_OVERHEAD + startVariableGas - gasleft();
        }
        // fee module monitors its own gas usage
        (uint256 executionFee, address executionFeeToken, bool inZeroFeeWindow) =
            feeModule.onExecuteJob(_index, job.executionWindow, job.zeroFeeWindow, executionTime, totalGas);

        if(executionFee > 0) {
            // transfer fee to fee recipient
            // we try to transfer from sponsor first, if that fails and sponsorFallbackToOwner is true, we transfer from owner and set sponsor to owner
            if(!ERC20(executionFeeToken).safeTransferFromNoRevert(job.sponsor, _feeRecipient, executionFee)) {
                if(job.sponsorFallbackToOwner) {
                    ERC20(executionFeeToken).safeTransferFrom(job.owner, _feeRecipient, executionFee);
                    job.sponsor = job.owner;
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
        return (job.creationTime, executionFee, executionFeeToken, uint8(job.executionModule), uint8(job.feeModule), inZeroFeeWindow);
    }

    /**
     * @notice Deactivates a job preventing it from being executed.
     * @param _index Index of the job in the jobs array.
     */
    function deactivateJob(uint256 _index) public override {
        Job storage job = jobs[_index];
        if (msg.sender != job.owner) revert Unauthorized();
        job.active = false;
        emit JobDeactivated(_index, job.owner, address(job.application));
    }

    /**
     * @notice Deletes the job from the jobs array and calls onDeleteJob on execution module and application.
     * @param _index The index of the job in the jobs array.
     */
    function deleteJob(uint256 _index) public override nonReentrant {
        if (msg.sender != jobs[_index].owner) revert Unauthorized();
        _deleteJob(_index);
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
     * @notice Revokes sponsorship of a job. This will make the owner the sponsor.
     * @notice Only callable by the sponsor or owner of the job.
     * @param _index Index of the job in the jobs array.
     */
    function revokeSponsorship(uint256 _index) public override {
        Job storage job = jobs[_index];

        if(msg.sender == job.sponsor) {
            if(job.sponsorFallbackToOwner) {
                job.sponsor = job.owner;
            } else {
                job.sponsor = address(0);
            }
        } else if (msg.sender == job.owner) {
            job.sponsor = job.owner;
        } else {
            revert Unauthorized();
        }
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
        // if job.sponsorCanUpdateFeeModule both sponsor and owner can update fee module
        // if !job.sponsorCanUpdateFeeModule only owner can update fee module
        if (msg.sender != job.owner && !(job.sponsorCanUpdateFeeModule && msg.sender == job.sponsor)) {
            revert Unauthorized();
        }

        // Check that job is not in execution mode
        (address executionModuleAddress,) = coordinator.modules(uint8(job.executionModule));
        if (IExecutionModule(executionModuleAddress).jobIsInExecutionMode(_feeModuleInput.index, job.executionWindow)) {
            revert JobInExecutionMode();
        }

        bool hasSponsorship = _sponsor != address(0);
        if (hasSponsorship) {
            if (block.timestamp > _feeModuleInput.deadline) revert SignatureExpired(_feeModuleInput.deadline);
            _useUnorderedNonce(_sponsor, _feeModuleInput.nonce, !_feeModuleInput.reusableNonce);
            if(!publicERC6492Validator.isValidSignatureNowAllowSideEffects(_sponsor, _hashTypedData(_feeModuleInput.hash()), _sponsorSignature)) revert InvalidSignature();
            job.sponsor = _sponsor;
        } else {
            job.sponsor = job.owner;
        }

        (address currentFeeModuleAddress,) = coordinator.modules(uint8(job.feeModule));
        IFeeModule currentFeeModule = IFeeModule(currentFeeModuleAddress);
        if (_feeModuleInput.feeModule == job.feeModule) {
            // Update existing fee module with new data
            currentFeeModule.onUpdateData(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor);
        } else {
            // Migrate to new fee module
            (address newFeeModuleAddress, bool isNotFeeModule) = coordinator.modules(uint8(_feeModuleInput.feeModule));
            if(isNotFeeModule) revert InvalidModule();
            IFeeModule newFeeModule = IFeeModule(newFeeModuleAddress);
            currentFeeModule.onDeleteJob(_feeModuleInput.index);
            newFeeModule.onCreateJob(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            job.feeModule = _feeModuleInput.feeModule;
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor);
        }
    }

    /**
     * @notice Gets the length of the job array.
     * @return length The length of the job array.
     */
    function getJobsArrayLength() public view override returns (uint256) {
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
