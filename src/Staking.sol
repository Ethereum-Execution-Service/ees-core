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

    // in seconds
    uint8 internal immutable roundBuffer;

    address internal immutable stakingToken;
    uint256 internal immutable stakingAmount;
    // minimum amount of staking balance required to be eligible to execute
    uint256 internal immutable stakingBalanceThreshold;
    // amount to slash from the staker upon inactivity.
    uint256 internal immutable slashingAmount;

    // in seconds
    uint8 internal immutable roundDuration;

    uint8 internal immutable roundsPerEpoch;
    // in seconds
    uint8 internal immutable epochDuration;

    // in seconds
    uint8 internal immutable commitPhaseDuration;

    // in seconds
    uint8 internal immutable revealPhaseDuration;

    // in seconds
    uint8 internal immutable selectionPhaseDuration;

    // true for an index if the executor has executed in that round
    bool[] public executedRounds;

    address[] public activeStakers;
    mapping(address => StakerInfo) public stakerInfo;

    bytes32 public seed;
    uint256 public epoch;

    mapping(address => CommitData) public commitmentMap;

    constructor(StakingSpec memory _spec) {
        require(
            _spec.stakingBalanceThreshold <= _spec.stakingAmount,
            "Staking: threshold must be less than or equal to staking amount"
        );
        require(
            _spec.slashingAmount <= _spec.stakingBalanceThreshold,
            "Staking: slashing amount must be less than or equal to staking threshold amount"
        );
        stakingToken = _spec.stakingToken;
        stakingAmount = _spec.stakingAmount;
        stakingBalanceThreshold = _spec.stakingBalanceThreshold;
        slashingAmount = _spec.slashingAmount;
        roundDuration = _spec.roundDuration;
        roundsPerEpoch = _spec.roundsPerEpoch;
        roundBuffer = _spec.roundBuffer;
        selectionPhaseDuration = _spec.commitPhaseDuration + _spec.revealPhaseDuration;
        epochDuration = selectionPhaseDuration + (roundDuration + roundBuffer) * roundsPerEpoch;
        commitPhaseDuration = _spec.commitPhaseDuration;
        revealPhaseDuration = _spec.revealPhaseDuration;
        executedRounds = new bool[](roundsPerEpoch);
    }

    function stake() public {
        // check if already staked
        if (stakerInfo[msg.sender].balance > 0) revert AlreadyStaked();

        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), stakingAmount);

        _activateStaker(msg.sender);
        stakerInfo[msg.sender] =
            StakerInfo({balance: stakingAmount, active: true, initialized: true, arrayIndex: numberOfActiveStakers});
        numberOfActiveStakers += 1;
    }

    function unstake() public {
        if (block.timestamp < epochEndTime && block.timestamp >= epochEndTime - epochDuration + revealPhaseDuration) {
            revert InvalidBlockTime();
        }

        StakerInfo memory staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotAStaker();
        delete stakerInfo[msg.sender];

        delete commitmentMap[msg.sender];

        // if staker is active, deactivate it
        if (staker.active) {
            address lastStaker = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStaker].arrayIndex = staker.arrayIndex;
            numberOfActiveStakers -= 1;
        }
        ERC20(stakingToken).safeTransfer(msg.sender, staker.balance);
    }

    function topup(uint256 _amount) public {
        StakerInfo storage staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotAStaker();
        ERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        staker.balance += _amount;
        if (!staker.active && staker.balance >= stakingAmount) {
            _activateStaker(msg.sender);
            staker.active = true;
            numberOfActiveStakers += 1;
        }
    }

    function slashInactiveStaker() public {
        // have to check if there nothing was executed (function wasnt called) in the last round
        if (block.timestamp < epochEndTime - epochDuration + selectionPhaseDuration || block.timestamp >= epochEndTime)
        {
            revert InvalidBlockTime();
        }
        uint256 timeIntoRounds = epochDuration - selectionPhaseDuration - (epochEndTime - block.timestamp);
        uint8 roundTotalDuration = roundDuration + roundBuffer;
        // revert if in execution phase of the round
        if (timeIntoRounds % roundTotalDuration < roundDuration) revert NotInBufferOfRound();
        // current round within the epoch
        uint256 round = timeIntoRounds / roundTotalDuration;

        // compute selected index for round
        uint256 stakerIndex = uint256(keccak256(abi.encodePacked(seed, round))) % uint256(numberOfActiveStakers);

        // check whether the selected staker has executed in thus round
        if (executedRounds[round]) revert RoundExecuted();

        address stakerAddress = activeStakers[stakerIndex];
        _slash(slashingAmount, stakerAddress, msg.sender);
        executedRounds[round] = true;
    }

    function slashCommitter(address _committer) public {
        if (block.timestamp < epochEndTime - epochDuration + commitPhaseDuration || block.timestamp >= epochEndTime) {
            revert InvalidBlockTime();
        }
        CommitData storage commitData = commitmentMap[_committer];
        if (commitData.epoch != epoch) revert OldEpoch();
        if (commitData.revealed) revert CommitmentRevealed();
        // slash the committer
        _slash(slashingAmount, _committer, msg.sender);
        commitData.revealed = true;
    }

    function initiateEpoch() public {
        if (block.timestamp < epochEndTime) revert InvalidBlockTime();
        epochEndTime = block.timestamp + epochDuration;

        assembly {
            let len := sload(executedRounds.slot) // Load the length of the array (dynamic arrays store length in slot)
            let startSlot := add(executedRounds.slot, 1) // First element of the array is stored in slot + 1
            for { let i := 0 } lt(i, len) { i := add(i, 1) } { sstore(add(startSlot, i), 0) } // Set each element to zero
        }

        epoch += 1;
        seed = keccak256(abi.encodePacked(block.timestamp, block.timestamp));
    }

    function commit(bytes32 _commitment) public {
        if (block.timestamp >= epochEndTime - epochDuration + revealPhaseDuration) {
            revert InvalidBlockTime();
        }
        // check if active staker
        if (!stakerInfo[msg.sender].active) revert NotAStaker();

        commitmentMap[msg.sender] = CommitData({commitment: _commitment, epoch: epoch, revealed: false});
    }

    function reveal(bytes calldata _signature) public {
        // do time checks
        if (
            block.timestamp < epochEndTime - epochDuration + revealPhaseDuration
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

    function _verifySignature(uint256 _epochNum, uint256 _chainId, bytes memory _signature, address _expectedSigner)
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
        address lastStaker = activeStakers[numberOfActiveStakers - 1];
        activeStakers[_index] = lastStaker;
        delete activeStakers[numberOfActiveStakers - 1];
        return lastStaker;
    }

    function _slash(uint256 _amount, address _stakerAddress, address _recipient) private {
        StakerInfo storage staker = stakerInfo[_stakerAddress];
        staker.balance -= _amount;

        if (staker.balance < stakingBalanceThreshold) {
            // index in activeStakers array
            address lastStakerAddress = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStakerAddress].arrayIndex = staker.arrayIndex;
            staker.active = false;
            numberOfActiveStakers -= 1;
        }
        // reward slasher
        ERC20(stakingToken).safeTransfer(_recipient, _amount / 2);
    }
}
