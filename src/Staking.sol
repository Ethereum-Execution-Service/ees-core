// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink-contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink-contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IStaking} from "./interfaces/IStaking.sol";

contract Staking is IStaking, VRFConsumerBaseV2Plus {
    using SafeTransferLib for ERC20;

    uint256 public roundEndBlock;
    bool public executionInRound;
    bool public epochRequested;

    uint256 public epochEndBlock;

    uint40 public numberOfActiveStakers;

    // in blocks
    uint8 internal immutable s_epochBuffer;
    uint8 internal immutable s_roundBuffer;

    address internal immutable s_stakingToken;
    uint256 internal immutable s_stakingAmount;
    // minimum amount of staking balance required to be eligible to execute
    uint256 internal immutable s_stakingBalanceThreshold;
    // amount to slash from the staker upon inactivity.
    uint256 internal immutable s_slashingAmount;
    // number of blocks inactive executor can be slashed within
    uint8 internal immutable s_slashingWindow;
    // in blocks
    uint8 internal immutable s_roundDuration;
    uint8 internal immutable s_roundsPerEpoch;
    uint8 internal immutable s_epochLength;

    uint256 public requestId;

    // one index per round in order to select a staker
    uint40[] public selectedIndices;
    // true for an index if the executor has executed in that round
    bool[] public executedRounds;

    uint256 public subscriptionId;
    // https://docs.chain.link/vrf/v2-5/supported-networks
    bytes32 public keyHash = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;

    address[] public activeStakers;
    mapping(address => StakerInfo) public stakerInfo;

    constructor(StakingSpec memory _spec, uint256 _subscriptionId, address _vrfCoordinator)
        VRFConsumerBaseV2Plus(_vrfCoordinator)
    {
        require(
            _spec.stakingBalanceThreshold <= _spec.stakingAmount,
            "Staking: threshold must be less than or equal to staking amount"
        );
        require(
            _spec.slashingAmount <= _spec.stakingBalanceThreshold,
            "Staking: slashing amount must be less than or equal to staking threshold amount"
        );
        subscriptionId = _subscriptionId;
        s_stakingToken = _spec.stakingToken;
        s_stakingAmount = _spec.stakingAmount;
        s_stakingBalanceThreshold = _spec.stakingBalanceThreshold;
        s_slashingAmount = _spec.slashingAmount;
        s_roundDuration = _spec.roundDuration;
        s_roundsPerEpoch = _spec.roundsPerEpoch;
        s_slashingWindow = _spec.slashingWindow;
        s_roundBuffer = _spec.roundBuffer;
        s_epochBuffer = _spec.epochBuffer;
        s_epochLength = (s_roundDuration + s_roundBuffer) * s_roundsPerEpoch;

        selectedIndices = new uint40[](s_roundsPerEpoch);
        executedRounds = new bool[](s_roundsPerEpoch);
    }

    function stake() public {
        // check if already staked
        if (stakerInfo[msg.sender].balance > 0) revert AlreadyStaked();

        ERC20(s_stakingToken).transferFrom(msg.sender, address(this), s_stakingAmount);

        _activateStaker(msg.sender);
        stakerInfo[msg.sender] =
            StakerInfo({balance: s_stakingAmount, active: true, initialized: true, arrayIndex: numberOfActiveStakers});
        numberOfActiveStakers += 1;
    }

    function unstake() public {
        // CANNOT DO WHILE IN A AN EPOCH or slashing window - make check
        if (block.number < epochEndBlock + s_slashingWindow) revert EpochNotDone();
        StakerInfo memory staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotAStaker();
        delete stakerInfo[msg.sender];

        // if staker is active, deactivate it
        if (staker.active) {
            address lastStaker = _deactivateStaker(staker.arrayIndex);
            stakerInfo[lastStaker].arrayIndex = staker.arrayIndex;
            numberOfActiveStakers -= 1;
        }
        ERC20(s_stakingToken).transfer(msg.sender, staker.balance);
    }

    function topup(uint256 _amount) public {
        StakerInfo storage staker = stakerInfo[msg.sender];
        if (!staker.initialized) revert NotAStaker();
        ERC20(s_stakingToken).transferFrom(msg.sender, address(this), _amount);
        staker.balance += _amount;
        if (!staker.active && staker.balance >= s_stakingAmount) {
            _activateStaker(msg.sender);
            staker.active = true;
            numberOfActiveStakers += 1;
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

    function slash(uint256 _index) public {
        // have to check if there nothing was executed (function wasnt called) in the last round
        if (block.number < epochEndBlock) revert EpochNotDone();
        if (block.number >= epochEndBlock + s_slashingWindow) revert SlashingWindowOver();
        if (executedRounds[_index]) revert RoundExecuted();

        uint40 activeStakerIndex = selectedIndices[_index];
        address stakerAddress = activeStakers[activeStakerIndex];
        StakerInfo storage staker = stakerInfo[stakerAddress];
        staker.balance -= s_slashingAmount;

        if (staker.balance < s_stakingBalanceThreshold) {
            // index in activeStakers array
            address lastStakerAddress = _deactivateStaker(activeStakerIndex);
            stakerInfo[lastStakerAddress].arrayIndex = staker.arrayIndex;
            stakerInfo[stakerAddress].active = false;
            numberOfActiveStakers -= 1;
        }
        // reward slasher
        ERC20(s_stakingToken).transfer(msg.sender, s_slashingAmount / 2);
        executedRounds[_index] = true;
    }

    function fulfillRandomWords(uint256, /* _requestId */ uint256[] calldata _randomWords) internal override {
        if (msg.sender != address(s_vrfCoordinator)) revert OnlyCoordinator();

        // need to make sure it cannot be called again
        if (!epochRequested) revert RequestAlreadyFulfilled();
        if (_randomWords.length != s_roundsPerEpoch) revert WrongNumberOfRandomWords();
        for (uint256 i = 0; i < _randomWords.length; ++i) {
            selectedIndices[i] = uint40(_randomWords[i] % numberOfActiveStakers);
        }

        /*
        assembly {
          let ptr := selectedIndices.slot

          for { let i := 0 } lt(i, ROUNDS_PER_EPOCH) { i := add(i, 1) } {
              let randomWord := calldataload(add(_randomWords.offset, mul(i, 0x20)))
              sstore(add(ptr, i), mod(randomWord, numberOfActiveStakers))
          }
        } 
        */

        epochRequested = false;
        epochEndBlock = block.number + s_epochLength;
    }

    function requestRound() public {
        if (epochRequested) revert EpochAlreadyRequested();
        if (block.number < epochEndBlock + s_epochBuffer) revert EpochNotDone();
        epochRequested = true;
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 100000,
                numWords: s_roundsPerEpoch,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );
        executionInRound = false;
    }
}
