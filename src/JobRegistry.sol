// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IExecutionModule} from "./interfaces/IExecutionModule.sol";
import {IFeeModule} from "./interfaces/IFeeModule.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {SignatureVerification} from "./libraries/SignatureVerification.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";
import {JobSpecificationHash} from "./libraries/JobSpecificationHash.sol";
import {FeeModuleInputHash} from "./libraries/FeeModuleInputHash.sol";
import {SignatureExpired, InvalidNonce} from "./PermitErrors.sol";
import {EIP712} from "./EIP712.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

/// @author Victor Brevig
/// @notice JobRegistry keeps track of all jobs in the EES. It is through this contract jobs are created, executed and deleted.
contract JobRegistry is IJobRegistry, EIP712, ReentrancyGuard, Owned {
    using SignatureVerification for bytes;
    using SafeTransferLib for ERC20;
    using JobSpecificationHash for JobSpecification;
    using FeeModuleInputHash for FeeModuleInput;

    address internal treasury;
    uint8 public protocolFeeRatio;
    Job[] public jobs;

    IExecutionModule[] public executionModules;
    IFeeModule[] public feeModules;

    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    constructor(address _owner, address _treasury, uint8 _protocolFeeRatio) Owned(_owner) {
        treasury = _treasury;
        protocolFeeRatio = _protocolFeeRatio;
    }

    /**
     * @notice Creates a job with given specification and stores it in the jobs array. It calls the callback funcitons onCreateJob on both the execution module and the application.
     * @notice The nonce and deadline fieds inside _specification are only considered if _hasSponsorship is true.
     * @param _specification Struct containing specifications of the job.
     * @param _sponsor The address paying execution fees related to the job.
     * @param _sponsorSignature EIP-712 signature of _specification signed by _sponsor.
     * @param _hasSponsorship Flag which is true if the job is created with a sponsor. If false, msg.sender is set to sponsor and _sponsorSignature is not verified.
     * @param _index The index in the jobs array which the job should be created at. If this is greater than or equal to jobs.length then the array will be extended, otherwise it will reuse an index.
     */
    function createJob(
        JobSpecification calldata _specification,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bool _hasSponsorship,
        uint256 _index
    ) public override returns (uint256 index) {
        if (_hasSponsorship) {
            if (block.timestamp > _specification.deadline) revert SignatureExpired(_specification.deadline);
            _useUnorderedNonce(_sponsor, _specification.nonce);
            _sponsorSignature.verify(_hashTypedData(_specification.hash()), _sponsor);
        }

        bool reuseIndex = _index < jobs.length;
        index = reuseIndex ? _index : jobs.length;

        IExecutionModule executionModule = executionModules[uint8(_specification.executionModule)];
        IFeeModule feeModule = feeModules[uint8(_specification.feeModule)];

        bool initialExecution =
            executionModule.onCreateJob(index, _specification.executionModuleInput, _specification.executionWindow);
        feeModule.onCreateJob(index, _specification.feeModuleInput);

        _specification.application.onCreateJob(
            index, _specification.executionModule, msg.sender, _specification.applicationInput
        );

        if (initialExecution) {
            _specification.application.onExecuteJob(index, msg.sender, 0);
            emit JobExecuted(index, msg.sender, address(_specification.application), 0, 0, address(0));
        }

        Job memory newJob = Job({
            owner: msg.sender,
            sponsor: _hasSponsorship ? _sponsor : msg.sender,
            application: _specification.application,
            executionCounter: initialExecution ? 1 : 0,
            maxExecutions: _specification.maxExecutions,
            executionModule: _specification.executionModule,
            feeModule: _specification.feeModule,
            executionWindow: _specification.executionWindow
        });

        if (reuseIndex) {
            Job storage job = jobs[_index];
            if (job.owner != address(0)) revert JobAlreadyExistsAtIndex();
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
    function execute(uint256 _index, address _feeRecipient, bytes calldata _verificationData)
        public
        override
        nonReentrant
        returns (uint256 executionFee, address executionFeeToken)
    {
        Job storage job = jobs[_index];

        // job.owner can only be 0 if job was deleted
        if (job.owner == address(0)) revert JobIsDeleted();

        // check number of executions does not exceed max
        // maxExecutions = 0 means no limit
        if (job.maxExecutions != 0 && job.executionCounter >= job.maxExecutions) {
            revert MaxExecutionsExceeded();
        }

        IExecutionModule executionModule = executionModules[uint8(job.executionModule)];
        IFeeModule feeModule = feeModules[uint8(job.feeModule)];

        uint256 gasBefore = gasleft();

        (uint256 executionTime) = executionModule.onExecuteJob(_index, job.executionWindow, _verificationData);
        job.application.onExecuteJob(_index, job.owner, job.executionCounter);

        (executionFee, executionFeeToken) =
            feeModule.onExecuteJob(_index, msg.sender, job.executionWindow, executionTime, gasBefore - gasleft());

        // transfer protocol fee
        uint256 protocolFee = executionFee / protocolFeeRatio;
        uint256 executorFee;
        unchecked {
            executorFee = executionFee - protocolFee;
        }
        ERC20(executionFeeToken).safeTransferFrom(job.sponsor, treasury, protocolFee);
        // transfer executor fee
        ERC20(executionFeeToken).safeTransferFrom(job.sponsor, _feeRecipient, executorFee);

        emit JobExecuted(
            _index, job.owner, address(job.application), job.executionCounter, executionFee, executionFeeToken
        );

        job.executionCounter++;

        return (executionFee, executionFeeToken);
    }

    /**
     * @notice Deletes the job from the jobs array and calls onDeleteJob on execution module and application.
     * @param _index The index of the job in the jobs array.
     */
    function deleteJob(uint256 _index) public override {
        Job memory job = jobs[_index];

        IExecutionModule executionModule = executionModules[uint8(job.executionModule)];
        IFeeModule feeModule = feeModules[uint8(job.feeModule)];

        // if the job is expired or max executions hit, anyone can delete the job
        if (
            !(msg.sender == job.owner) && !executionModule.jobIsExpired(_index, job.executionWindow)
                && (job.maxExecutions == 0 || job.executionCounter < job.maxExecutions)
        ) {
            revert Unauthorized();
        }
        delete jobs[_index];

        // these should never revert, the owner should always be able to delete a job
        executionModule.onDeleteJob(_index);
        feeModule.onDeleteJob(_index);

        try job.application.onDeleteJob(_index, job.owner) {
            emit JobDeleted(_index, job.owner, address(job.application));
        } catch (bytes memory revertData) {
            emit ApplicationRevertedUponJobDeletion(_index, job.owner, address(job.application), revertData);
        }
    }

    /**
     * @notice Revokes sponsorship of a job. This will make the owner the sponsor.
     * @notice Only callable by the sponsor or owner of the job.
     * @param _index Index of the job in the jobs array.
     */
    function revokeSponsorship(uint256 _index) public override {
        Job storage job = jobs[_index];
        if (msg.sender != job.sponsor && msg.sender != job.owner) revert Unauthorized();
        job.sponsor = job.owner;
    }

    /**
     * @notice Pushes an execution module to the executionModules array.
     * @notice Only callable by the owner.
     * @param _module Execution module to be added.
     */
    function addExecutionModule(IExecutionModule _module) public override onlyOwner {
        executionModules.push(_module);
    }

    /**
     * @notice Pushes a fee module to the feeModules array.
     * @notice Only callable by the owner.
     * @param _module Fee module to be added.
     */
    function addFeeModule(IFeeModule _module) public override onlyOwner {
        feeModules.push(_module);
    }

    /**
     * @notice Updates data in a fee module or migrates to other fee module.
     * @notice Removes current sponsorship from the job.
     * @param _feeModuleInput Signable struct containing the index of the job and the data to be updated.
     * @param _sponsor The address paying execution fees related to the job.
     * @param _sponsorSignature EIP-712 signature of _feeModuleInput signed by _sponsor.
     * @param _hasSponsorship Flag which is true if the change is sponsored.
     */
    function updateFeeModule(
        FeeModuleInput calldata _feeModuleInput,
        address _sponsor,
        bytes calldata _sponsorSignature,
        bool _hasSponsorship
    ) public override {
        Job storage job = jobs[_feeModuleInput.index];
        if (job.owner != msg.sender) revert Unauthorized();
        if (_hasSponsorship) {
            if (block.timestamp > _feeModuleInput.deadline) revert SignatureExpired(_feeModuleInput.deadline);
            _useUnorderedNonce(_sponsor, _feeModuleInput.nonce);
            _sponsorSignature.verify(_hashTypedData(_feeModuleInput.hash()), _sponsor);
            job.sponsor = _sponsor;
        } else {
            job.sponsor = job.owner;
        }
        // Check that job is not in execution mode
        IExecutionModule executionModule = executionModules[uint8(job.executionModule)];
        if (executionModule.jobIsInExecutionMode(_feeModuleInput.index, job.executionWindow)) {
            revert JobInExecutionMode();
        }

        IFeeModule currentFeeModule = feeModules[uint8(job.feeModule)];
        if (_feeModuleInput.feeModule == job.feeModule) {
            // Update existing fee module with new data
            currentFeeModule.onUpdateData(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor);
        } else {
            // Migrate to new fee module
            IFeeModule newFeeModule = feeModules[uint8(_feeModuleInput.feeModule)];
            currentFeeModule.onDeleteJob(_feeModuleInput.index);
            newFeeModule.onCreateJob(_feeModuleInput.index, _feeModuleInput.feeModuleInput);
            job.feeModule = _feeModuleInput.feeModule;
            emit FeeModuleUpdate(_feeModuleInput.index, job.owner, job.sponsor);
        }
    }

    /**
     * @notice Updates protocol fee ratio.
     * @param _protocolFeeRatio The new protocol fee ratio.
     */
    function updateProtocolFeeRatio(uint8 _protocolFeeRatio) public override onlyOwner {
        protocolFeeRatio = _protocolFeeRatio;
    }

    /**
     * @notice Withdraws protocol fee from the contract.
     * @param _token The ERC-20 token to withdraw.
     * @param _recipient The address to receive the withdrawn tokens.
     */
    function withdrawProtocolFee(address _token, address _recipient) public override onlyOwner {
        ERC20(_token).safeTransfer(_recipient, ERC20(_token).balanceOf(address(this)));
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
     * @param wordPos The position in the nonce bitmap (index of the word) where the nonces should be invalidated.
     * @param mask A bitmask where each bit set to 1 invalidates the corresponding nonce in the bitmap.
     */
    function invalidateUnorderedNonces(uint256 wordPos, uint256 mask) external {
        nonceBitmap[msg.sender][wordPos] |= mask;
        emit UnorderedNonceInvalidation(msg.sender, wordPos, mask);
    }

    /**
     * @notice Returns the index of the bitmap and the bit position within the bitmap. Used for unordered nonces
     * @notice Taken from the PERMIT-2's SignatureTransfer contract https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol
     * @param nonce The nonce to get the associated word and bit positions
     * @return wordPos The word position or index into the nonceBitmap
     * @return bitPos The bit position
     * @dev The first 248 bits of the nonce value is the index of the desired bitmap
     * @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
     */
    function bitmapPositions(uint256 nonce) private pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }

    /**
     * @notice Checks whether a nonce is taken and sets the bit at the bit position in the bitmap at the word position
     * @notice Taken from the PERMIT-2's SignatureTransfer contract https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol
     * @param from The address to use the nonce at
     * @param nonce The nonce to spend
     */
    function _useUnorderedNonce(address from, uint256 nonce) internal {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;
        uint256 flipped = nonceBitmap[from][wordPos] ^= bit;

        if (flipped & bit == 0) revert InvalidNonce();
    }
}
