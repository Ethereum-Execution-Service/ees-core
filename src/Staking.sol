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
    uint8 internal immutable epochBuffer;

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
        epochBuffer = _spec.epochBuffer;
        selectionPhaseDuration = _spec.commitPhaseDuration + _spec.revealPhaseDuration;
        epochDuration = selectionPhaseDuration + totalRoundDuration * roundsPerEpoch;
        commitPhaseDuration = _spec.commitPhaseDuration;
        revealPhaseDuration = _spec.revealPhaseDuration;
    }

    function stake() public {
        // not allowed to stake during rounds, numberOfActiveStakers should remain const in that phase
        if (block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration && block.timestamp < epochEndTime)
        {
            revert InvalidBlockTime();
        }

        // check if already staked
        if (stakerInfo[msg.sender].balance > 0) revert AlreadyStaked();

        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), stakingAmount);

        _activateStaker(msg.sender);
        stakerInfo[msg.sender] = StakerInfo({
            balance: stakingAmount,
            active: true,
            initialized: true,
            arrayIndex: numberOfActiveStakers,
            latestExecutedEpoch: 0
        });
        unchecked {
            // number of active stakers should not exceed uint40
            numberOfActiveStakers++;
        }
    }

    function unstake() public {
        if (block.timestamp < epochEndTime && block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration) {
            // not allowed to unstake in reveal phase + rounds
            revert InvalidBlockTime();
        }

        StakerInfo memory staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotActiveStaker();
        delete stakerInfo[msg.sender];
        delete commitmentMap[msg.sender];

        // if staker is active, deactivate it
        if (staker.active) {
            address lastStaker = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStaker].arrayIndex = staker.arrayIndex;
        }
        ERC20(stakingToken).safeTransfer(msg.sender, staker.balance);
    }

    function topup(uint256 _amount) public {
        // not allowed to topup during rounds, numberOfActiveStakers should remain const in that phase
        if (block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration && block.timestamp < epochEndTime)
        {
            revert InvalidBlockTime();
        }
        StakerInfo storage staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotActiveStaker();
        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        unchecked {
            // sum of all user balances should not exceed uint256
            staker.balance += _amount;
        }
        if (!staker.active && staker.balance >= stakingAmount) {
            _activateStaker(msg.sender);
            staker.active = true;
            unchecked {
                // number of active stakers should not exceed uint40
                numberOfActiveStakers++;
            }
        }
    }

    function slashRoundInactiveStaker(address _staker, uint8 _round) public {
        if (block.timestamp < epochEndTime || block.timestamp >= epochEndTime + epochBuffer) {
            revert InvalidBlockTime();
        }
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

    function slashCommitter(address _committer) public {
        if (block.timestamp < epochEndTime || block.timestamp >= epochEndTime + epochBuffer) {
            revert InvalidBlockTime();
        }
        CommitData storage commitData = commitmentMap[_committer];
        if (commitData.epoch != epoch) revert OldEpoch();
        if (commitData.revealed) revert CommitmentRevealed();
        // slash the committer
        _slash(commitSlashingAmount, _committer, msg.sender);
        commitData.revealed = true;
    }

    function initiateEpoch() public {
        if (block.timestamp < epochEndTime + epochBuffer) revert InvalidBlockTime();
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

    function commit(bytes32 _commitment) public {
        if (block.timestamp >= epochEndTime - epochDuration + commitPhaseDuration) {
            revert InvalidBlockTime();
        }
        if (!stakerInfo[msg.sender].active) revert NotActiveStaker();

        commitmentMap[msg.sender] = CommitData({commitment: _commitment, epoch: epoch, revealed: false});
    }

    function reveal(bytes calldata _signature) public {
        // do time checks

        if (
            block.timestamp < epochEndTime - epochDuration + commitPhaseDuration
                || block.timestamp >= epochEndTime - epochDuration + selectionPhaseDuration
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

    function _splitSignature(bytes memory _sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (_sig.length != 65) revert InvalidSignatureLength();
        assembly {
            r := mload(add(_sig, 32))
            s := mload(add(_sig, 64))
            v := byte(0, mload(add(_sig, 96)))
        }
    }

    function _activateStaker(address _staker) private {
        if (numberOfActiveStakers < activeStakers.length) {
            // find the first empty slot and insert
            activeStakers[numberOfActiveStakers] = _staker;
        } else {
            // push at the end of the array
            activeStakers.push(_staker);
        }
    }

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
     * @dev Should only be called where the staker is active
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
}
