// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IStaking} from "./interfaces/IStaking.sol";

contract Staking is IStaking {
    using SafeTransferLib for ERC20;

    uint256 public roundEndBlock;
    bool public executionInRound;
    bool public epochRequested;

    uint256 public epochEndTime;

    uint40 public numberOfActiveStakers;

    address internal immutable stakingToken;
    uint256 internal immutable stakingAmount;
    // minimum amount of staking balance required to be eligible to execute
    uint256 internal immutable stakingBalanceThreshold;
    // amount to slash from the staker upon inactivity.
    uint256 internal immutable inactiveSlashingAmount;

    // amount to slash for committing without revealing
    uint256 internal immutable commitSlashingAmount;

    uint8 internal immutable roundsPerEpoch;

    // all in seconds
    uint8 internal immutable roundDuration;
    uint8 internal immutable roundBuffer;
    uint8 internal immutable epochDuration;
    uint8 internal immutable commitPhaseDuration;
    uint8 internal immutable revealPhaseDuration;
    uint8 internal immutable selectionPhaseDuration;
    uint8 internal immutable totalRoundDuration;
    // slashing phase
    uint8 internal immutable slashingDuration;

    address[] public activeStakers;
    mapping(address => StakerInfo) public stakerInfo;

    bytes32 public seed;
    uint192 public epoch;

    mapping(address => CommitData) public commitmentMap;

    constructor(StakingSpec memory _spec) {
        require(
            _spec.stakingBalanceThreshold <= _spec.stakingAmount,
            "Staking: threshold must be less than or equal to staking amount"
        );
        totalRoundDuration = _spec.roundDuration + _spec.roundBuffer;
        require(totalRoundDuration > 0, "Staking: round duration and buffer must be greater than 0");

        stakingToken = _spec.stakingToken;
        stakingAmount = _spec.stakingAmount;
        stakingBalanceThreshold = _spec.stakingBalanceThreshold;
        inactiveSlashingAmount = _spec.inactiveSlashingAmount;
        commitSlashingAmount = _spec.commitSlashingAmount;
        require(
            inactiveSlashingAmount + commitSlashingAmount <= stakingBalanceThreshold,
            "Staking: invalid slashing amounts"
        );
        roundDuration = _spec.roundDuration;
        roundsPerEpoch = _spec.roundsPerEpoch;
        roundBuffer = _spec.roundBuffer;
        slashingDuration = _spec.slashingDuration;
        selectionPhaseDuration = _spec.commitPhaseDuration + _spec.revealPhaseDuration;
        epochDuration = selectionPhaseDuration + totalRoundDuration * roundsPerEpoch;
        commitPhaseDuration = _spec.commitPhaseDuration;
        revealPhaseDuration = _spec.revealPhaseDuration;
    }

    /**
     * @notice Stakes the stakingToken transfering the stakingAmount to the contract and activates the staker to be able to execute jobs.
     * @notice Caller must not be an already initialized staker. To increase balance use topup instead.
     * @notice Cannot be called during execution rounds and slashing window.
     * @dev Activates the staker, adding it to stakerInfo and  and increments numberOfActiveStakers.
     */
    function stake() public {
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime + slashingDuration
        ) {
            revert InvalidBlockTime();
        }
        if (stakerInfo[msg.sender].initialized) revert AlreadyStaked();

        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), stakingAmount);

        stakerInfo[msg.sender] = StakerInfo({
            balance: stakingAmount,
            active: true,
            initialized: true,
            arrayIndex: numberOfActiveStakers,
            latestExecutedEpoch: 0
        });
        _activateStaker(msg.sender);
    }

    /**
     * @notice Unstakes the stakingToken and transfers the balance from the contract to the staker and deactivates the staker.
     * @notice Cannot be called during reveal phase, execution rounds and slashing duration.
     * @dev If the staker is active it is deactivated removing it from activeStakers and numberOfActiveStakers is decremented. The staker is removed from stakerInfo.
     */
    function unstake() public {
        if (
            block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration
                && block.timestamp < epochEndTime + slashingDuration
        ) {
            revert InvalidBlockTime();
        }

        StakerInfo memory staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotActiveStaker();
        delete stakerInfo[msg.sender];
        delete commitmentMap[msg.sender];

        if (staker.active) {
            address lastStaker = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStaker].arrayIndex = staker.arrayIndex;
        }
        ERC20(stakingToken).safeTransfer(msg.sender, staker.balance);
    }

    /**
     * @notice Increases the staking balance of the staker by the given amount and activates the staker if end balance is above threshold.
     * @notice Cannot be called during execution rounds and slashing window.
     * @param _amount The amount to topup the staking balance with stakingToken.
     */
    function topup(uint256 _amount) public {
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                && block.timestamp < epochEndTime + slashingDuration
        ) {
            revert InvalidBlockTime();
        }

        StakerInfo storage staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotActiveStaker();
        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        unchecked {
            // sum of all user balances will never exceed uint256 max value
            staker.balance += _amount;
        }
        if (!staker.active && staker.balance >= stakingAmount) {
            staker.active = true;
            _activateStaker(msg.sender);
        }
    }

    /**
     * @notice Slashes the staker for not executing in the given round with inactiveSlashingAmount.
     * @notice If stakers balance goes below threshold, staker is deactivated.
     * @notice Cannot only be called during slashing window.
     * @param _staker The address of the staker to be slashed.
     * @param _round The round the staker is being slashed for.
     */
    function slashRoundInactiveStaker(address _staker, uint8 _round) public {
        if (block.timestamp >= epochEndTime + slashingDuration || block.timestamp < epochEndTime) {
            revert InvalidBlockTime();
        }
        if (_round >= roundsPerEpoch) revert RoundExceedingTotal();

        // check if the staker did execute this epoch
        StakerInfo storage staker = stakerInfo[_staker];
        // do we have to check if staker is active? no, becasue we verify that staker.arayIndex is selected
        // verify staker.arrayIndex is selected
        uint256 stakerIndex = uint256(keccak256(abi.encodePacked(seed, _round))) % uint256(numberOfActiveStakers);
        if (staker.arrayIndex != stakerIndex) revert StakerNotSelectedForRound();
        if (staker.latestExecutedEpoch == epoch) revert RoundExecuted();

        // prevent from slashing again
        staker.latestExecutedEpoch = epoch;

        _slash(inactiveSlashingAmount, _staker, msg.sender);
    }

    /**
     * @notice Slashes the staker for committing without revealing with commitSlashingAmount.
     * @notice If stakers balance goes below threshold, staker is deactivated.
     * @notice Cannot only be called during slashing window.
     * @param _committer The address of the staker to be slashed.
     */
    function slashCommitter(address _committer) public {
        if (block.timestamp >= epochEndTime + slashingDuration || block.timestamp < epochEndTime) {
            revert InvalidBlockTime();
        }
        CommitData storage commitData = commitmentMap[_committer];
        if (commitData.epoch != epoch) revert OldEpoch();
        if (commitData.revealed) revert CommitmentRevealed();
        // slash the committer
        _slash(commitSlashingAmount, _committer, msg.sender);
        commitData.revealed = true;
    }

    /**
     * @notice Initiates a new epoch by setting the epochEndTime to the current block.timestamp + epochDuration.
     * @notice Cannot be called before last epoch is done plut slashing duration has passed.
     */
    function initiateEpoch() public {
        if (block.timestamp < epochEndTime + slashingDuration) revert InvalidBlockTime();
        unchecked {
            // block.timestamp + uint8 will not reach uint256
            epochEndTime = block.timestamp + epochDuration;
        }

        unchecked {
            // number of epochs should not exceed uint192
            emit EpochInitiated(++epoch);
        }
        seed = keccak256(abi.encodePacked(block.timestamp, block.number, seed));
    }

    /**
     * @notice Commits the stakers siganture of the current epoch.
     * @notice Can only be called during commit phase.
     * @param _commitment The commitment to be stored for the staker.
     */
    function commit(bytes32 _commitment) public {
        if (block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration) {
            revert InvalidBlockTime();
        }
        if (!stakerInfo[msg.sender].active) revert NotActiveStaker();

        commitmentMap[msg.sender] = CommitData({commitment: _commitment, epoch: epoch, revealed: false});
    }

    /**
     * @notice Reveals the stakers signature of the current epoch.
     * @notice Can only be called during reveal phase.
     * @notice Caller must have committed in the same epoch.
     * @param _signature The signature to be verified and used to update the seed.
     */
    function reveal(bytes calldata _signature) public {
        if (
            block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
                || block.timestamp < epochEndTime - epochDuration + commitPhaseDuration
        ) {
            revert InvalidBlockTime();
        }

        if (!_verifySignature(epoch, block.chainid, _signature, msg.sender)) revert InvalidSignature();

        CommitData storage commitData = commitmentMap[msg.sender];
        if (commitData.commitment != keccak256(abi.encodePacked(_signature))) revert WrongCommitment();
        if (commitData.revealed) revert CommitmentRevealed();
        if (commitData.epoch != epoch) revert OldEpoch();

        commitData.revealed = true;
        seed = keccak256(abi.encodePacked(seed, _signature));
    }

    /**
     * @notice Activates the staker, adding it to activeStakers and increments numberOfActiveStakers.
     * @dev Should only be used together with setting stakerInfo.active to true.
     * @param _staker The address of the staker to be activated.
     */
    function _activateStaker(address _staker) private {
        if (numberOfActiveStakers < activeStakers.length) {
            // find the first empty slot and insert
            activeStakers[numberOfActiveStakers] = _staker;
        } else {
            // push at the end of the array
            activeStakers.push(_staker);
        }
        unchecked {
            // number of active stakers will never be more than uint40 max value in practise
            numberOfActiveStakers++;
        }
    }

    /**
     * @notice Deactivates the staker, removing it from activeStakers and decrements numberOfActiveStakers.
     * @dev Should only be called when the staker is active.
     * @dev Should only be used together with setting stakerInfo.active to false or deleting stakingInfo entry.
     * @param _index The index of the staker in activeStakers.
     * @return lastStaker The address of the last staker in activeStakers.
     */
    function _deactivateStaker(uint40 _index) private returns (address) {
        uint40 newNumberOfActiveStakers;
        unchecked {
            // here the staker is active, so numberOfActiveStakers should be greater than 0
            newNumberOfActiveStakers = --numberOfActiveStakers;
        }
        address lastStaker = activeStakers[newNumberOfActiveStakers];
        activeStakers[_index] = lastStaker;
        delete activeStakers[newNumberOfActiveStakers];
        return lastStaker;
    }

    /**
     * @notice Slashes the staker for the given amount and sends half to the recipient.
     * @dev Should only be called when the staker is active.
     * @param _amount The amount to slash from the staker.
     * @param _stakerAddress The address of the staker to be slashed.
     * @param _recipient The address to send half of the slashed amount to.
     */
    function _slash(uint256 _amount, address _stakerAddress, address _recipient) private {
        StakerInfo storage staker = stakerInfo[_stakerAddress];

        if ((staker.balance -= _amount) < stakingBalanceThreshold) {
            // index in activeStakers array
            address lastStakerAddress = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStakerAddress].arrayIndex = staker.arrayIndex;
            staker.active = false;
        }
        // reward slasher, how about putting it in the fee mapping? then it needs access
        ERC20(stakingToken).safeTransfer(_recipient, _amount / 2);
    }

    /**
     * @notice Verifies the signature of the staker for the given epoch and chainId.
     * @param _epochNum The epoch number to verify the signature for.
     * @param _chainId The chainId to verify the signature for.
     * @param _signature The signature to verify.
     * @param _expectedSigner The expected signer of the signature.
     * @return isValid Is true if the signature is valid, false otherwise.
     */
    function _verifySignature(uint192 _epochNum, uint256 _chainId, bytes memory _signature, address _expectedSigner)
        private
        pure
        returns (bool)
    {
        bytes32 messageHash = keccak256(abi.encodePacked(_epochNum, _chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        return ecrecover(ethSignedMessageHash, v, r, s) == _expectedSigner;
    }

    /**
     * @notice Splits the signature into r, s and v.
     * @param _sig The signature to split.
     * @return r The r value of the signature.
     * @return s The s value of the signature.
     * @return v The v value of the signature.
     */
    function _splitSignature(bytes memory _sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (_sig.length != 65) revert InvalidSignatureLength();
        assembly {
            r := mload(add(_sig, 32))
            s := mload(add(_sig, 64))
            v := byte(0, mload(add(_sig, 96)))
        }
    }
}
