// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {StdUtils} from "forge-std/src/StdUtils.sol";
import {IStaking} from "../src/interfaces/IStaking.sol";
import {SignatureGenerator} from "./utils/SignatureGenerator.sol";

contract StakingTest is Test, TokenProvider, SignatureGenerator, GasSnapshot {
    MockStaking staking;

    address defaultStakingToken;
    // same as staker
    address executor;
    uint256 executorPrivateKey;

    address secondExecutor;
    uint256 secondExecutorPrivateKey;

    address thirdExecutor;
    uint256 thirdExecutorPrivateKey;

    uint256 stakingAmount = 1000;
    uint256 stakingBalanceThreshold = 300;
    uint256 inactiveSlashingAmount = 200;
    uint256 commitSlashingAmount = 50;
    uint8 roundDuration = 15;
    uint8 roundsPerEpoch = 5;
    uint8 roundBuffer = 15;
    uint8 commitPhaseDuration = 15;
    uint8 revealPhaseDuration = 15;
    uint8 slashingDuration = 30;

    uint256 defaultEpochEndTime = 1000;

    function setUp() public {
        initializeERC20Tokens();
        defaultStakingToken = address(token0);

        IStaking.StakingSpec memory spec = IStaking.StakingSpec({
            stakingToken: defaultStakingToken,
            stakingAmount: stakingAmount,
            stakingBalanceThreshold: stakingBalanceThreshold,
            inactiveSlashingAmount: inactiveSlashingAmount,
            commitSlashingAmount: commitSlashingAmount,
            roundDuration: roundDuration,
            roundsPerEpoch: roundsPerEpoch,
            roundBuffer: roundBuffer,
            commitPhaseDuration: commitPhaseDuration,
            revealPhaseDuration: revealPhaseDuration,
            slashingDuration: slashingDuration
        });
        staking = new MockStaking(spec);
        staking.setEpochEndTime(defaultEpochEndTime);

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        secondExecutorPrivateKey = 0x43214321;
        secondExecutor = vm.addr(secondExecutorPrivateKey);

        thirdExecutorPrivateKey = 0x11111111;
        thirdExecutor = vm.addr(thirdExecutorPrivateKey);

        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(staking));
        setERC20TestTokens(secondExecutor);
        setERC20TestTokenApprovals(vm, secondExecutor, address(staking));
        setERC20TestTokens(thirdExecutor);
        setERC20TestTokenApprovals(vm, thirdExecutor, address(staking));
        setERC20TestTokens(address(staking));
    }

    function test_Stake(uint256 time) public {
        vm.assume(
            time < defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + staking.getSlashingDuration()
        );

        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        vm.warp(time);
        staking.stake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex, uint192 latestExecutedEpoch) =
            staking.stakerInfo(executor);
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
        assertEq(balance, stakingAmount, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(staking.activeStakers(0), executor, "not in active stakers array");
        assertEq(startBalanceExecutor - endBalanceExecutor, stakingAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol - startBalanceProtocol, stakingAmount, "protocol balance mismatch");
        assertEq(latestExecutedEpoch, 0, "latest executed epoch mismatch");
        assertEq(staking.getNumberOfActiveStakers(), 1, "number of active stakers mismatch");
    }

    function test_StakeInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration(),
            defaultEpochEndTime + staking.getSlashingDuration() - 1
        );
        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.stake();
    }

    function test_StakeArrayNotFull0() public {
        vm.prank(executor);
        staking.stake();
        vm.prank(secondExecutor);
        staking.stake();

        vm.warp(defaultEpochEndTime + staking.getSlashingDuration());
        vm.prank(executor);
        staking.unstake();
        vm.prank(thirdExecutor);
        staking.stake();

        assertEq(staking.activeStakers(0), secondExecutor, "0th index mismatch");
        assertEq(staking.activeStakers(1), thirdExecutor, "1st index mismatch");
        assertEq(staking.getActiveStakersLength(), 2, "array length mismatch");
    }

    function test_StakeArrayNotFull1() public {
        vm.prank(executor);
        staking.stake();

        vm.prank(secondExecutor);
        staking.stake();

        vm.warp(defaultEpochEndTime + staking.getSlashingDuration());
        vm.prank(secondExecutor);
        staking.unstake();

        vm.prank(thirdExecutor);
        staking.stake();

        assertEq(staking.activeStakers(0), executor, "0th index mismatch");
        assertEq(staking.activeStakers(1), thirdExecutor, "1st index mismatch");
        assertEq(staking.getActiveStakersLength(), 2, "array length mismatch");
    }

    function test_StakingWhenAlreadyStaked() public {
        vm.prank(executor);
        staking.stake();
        vm.prank(executor);
        vm.expectRevert(IStaking.AlreadyStaked.selector);
        staking.stake();
    }

    function test_UnstakeActiveStaker(uint192 time) public {
        vm.assume(
            time < defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + staking.getSlashingDuration()
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        staking.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex, uint192 latestExecutedEpoch) =
            staking.stakerInfo(executor);
        assertFalse(active, "active");
        assertFalse(initialized, "initialized");
        assertEq(balance, 0, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(staking.activeStakers(0), address(0), "in active stakers array");
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
        assertEq(latestExecutedEpoch, 0, "latest executed epoch mismatch");
        assertEq(staking.getNumberOfActiveStakers(), 0, "number of active stakers mismatch");
    }

    function test_UnstakeInactiveStaker() public {
        // should not modify activeStakers array when unstaking an inactive staker
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);

        staking.stake();
        staking.setStakerInfo(
            IStaking.StakerInfo({
                balance: stakingAmount,
                active: false,
                initialized: true,
                arrayIndex: 0,
                latestExecutedEpoch: 0
            }),
            executor
        );

        vm.warp(defaultEpochEndTime + staking.getSlashingDuration());
        vm.prank(executor);
        staking.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(staking.activeStakers(0), executor, "in active stakers array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeInvalidBlockTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime + staking.getSlashingDuration() - 1
        );
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.unstake();
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        vm.warp(defaultEpochEndTime + staking.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(IStaking.NotActiveStaker.selector);
        staking.unstake();
    }

    function test_TopupToAboveThreshold(uint256 time, uint256 topUpAmount, uint256 startingBalance) public {
        // should activate staker when balance after topup is above staking amount
        vm.assume(
            time < defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + staking.getSlashingDuration()
        );
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, stakingAmount, token0.balanceOf(executor));
        staking.setStakerInfo(
            IStaking.StakerInfo({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                latestExecutedEpoch: 0
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.warp(time);
        vm.prank(executor);
        staking.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,) = staking.stakerInfo(executor);
        assertTrue(active, "not active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
        assertEq(staking.getNumberOfActiveStakers(), 1, "number of active stakers mismatch");
    }

    function test_TopupToBelowThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should not activate staker when balance after topup is below staking amount
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, 0, stakingAmount - startingBalance - 1);
        staking.setStakerInfo(
            IStaking.StakerInfo({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                latestExecutedEpoch: 0
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,) = staking.stakerInfo(executor);
        assertFalse(active, "active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
    }

    function test_TopupNotAStaker() public {
        // should revert if not a staker
        vm.prank(executor);
        vm.expectRevert(IStaking.NotActiveStaker.selector);
        staking.topup(stakingAmount);
    }

    function test_TopupInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration(),
            defaultEpochEndTime + staking.getSlashingDuration() - 1
        );
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.topup(stakingAmount);
    }

    function test_Slashing(address slasher, uint256 time) public {
        // should slash staker balance and slasher should receive half of slashed amount. Staker should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(staking));
        time = bound(time, defaultEpochEndTime, defaultEpochEndTime + staking.getSlashingDuration() - 1);

        vm.prank(executor);
        staking.stake();
        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        staking.setEpoch(1);

        vm.warp(time);
        vm.prank(slasher);
        staking.slashRoundInactiveStaker(executor, 0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,) = staking.stakerInfo(executor);
        assertEq(balance, stakingAmount - inactiveSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher, uint40 epoch) public {
        // should revert with RoundExecuted if round was executed
        vm.prank(executor);
        staking.stake();
        vm.warp(defaultEpochEndTime);

        staking.setEpoch(epoch);
        staking.setStakerInfo(
            IStaking.StakerInfo({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                latestExecutedEpoch: epoch
            }),
            executor
        );

        vm.prank(slasher);
        vm.expectRevert(IStaking.RoundExecuted.selector);
        staking.slashRoundInactiveStaker(executor, 0);
    }

    function test_SlashingEndBalanceBelowThreshold(address slasher) public {
        // should slash staker balance and slasher should receive half of slashed amount. Staker should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(staking));
        vm.prank(executor);
        staking.stake();

        staking.setEpoch(1);
        staking.setStakerInfo(
            IStaking.StakerInfo({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                latestExecutedEpoch: 0
            }),
            executor
        );
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        vm.warp(defaultEpochEndTime);
        vm.prank(slasher);
        staking.slashRoundInactiveStaker(executor, 0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,) = staking.stakerInfo(executor);
        assertEq(balance, stakingBalanceThreshold + 1 - inactiveSlashingAmount, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
        assertEq(staking.getNumberOfActiveStakers(), 0, "number of active stakers mismatch");
    }

    function test_SlashingBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - 1);

        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.slashRoundInactiveStaker(executor, 0);
    }

    function test_SlashingAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + staking.getSlashingDuration(), type(uint192).max);

        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.slashRoundInactiveStaker(executor, 0);
    }

    function test_SlashingNotSelectedStaker(bytes32 seed, uint8 round, uint40 numOfActiveStakers) public {
        // should revert with StakerNotSelectedForRound if staker was not selected for round
        vm.assume(numOfActiveStakers > 0);
        round = uint8(bound(round, 0, roundsPerEpoch - 1));
        vm.prank(executor);
        staking.stake();
        staking.setSeed(seed);
        staking.setNumberOfActiveStakers(numOfActiveStakers);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, round))) % uint256(numOfActiveStakers) != 0);

        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        vm.expectRevert(IStaking.StakerNotSelectedForRound.selector);
        staking.slashRoundInactiveStaker(executor, round);
    }

    function test_SlashingRoundExceedingTotal(uint8 round) public {
        round = uint8(bound(round, roundsPerEpoch, type(uint8).max));
        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        vm.expectRevert(IStaking.RoundExceedingTotal.selector);
        staking.slashRoundInactiveStaker(executor, round);
    }

    function test_InitiateEpoch(address caller, uint256 time) public {
        time = bound(time, defaultEpochEndTime + staking.getSlashingDuration(), type(uint192).max);
        // should increase epochEndTime and increment epoch. Callable by anyone. Should set executedRounds to all false
        staking.setEpoch(0);
        vm.warp(time);
        vm.prank(caller);
        staking.initiateEpoch();
        assertEq(staking.epochEndTime(), time + staking.getEpochDuration(), "epoch mismatch");
        assertEq(staking.epoch(), 1, "epoch mismatch");
    }

    function test_InitiateBeforeTime(address caller, uint256 time) public {
        // should revert with EpochNotEnded if epochEndTime is not reached
        time = bound(time, 0, defaultEpochEndTime + staking.getSlashingDuration() - 1);
        vm.warp(time);
        vm.prank(caller);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.initiateEpoch();
    }

    function test_Commit(bytes32 commitment, uint192 epoch, uint256 time) public {
        // should go from defaultEpochEndTime - staking.getEpochDuration() to defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration(),
            defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration - 1
        );
        vm.prank(executor);
        staking.stake();

        staking.setEpoch(epoch);
        vm.warp(time);
        vm.prank(executor);
        staking.commit(commitment);

        (bytes32 commitmentSet, uint192 epochSet, bool revealedSet) = staking.commitmentMap(executor);
        assertEq(commitmentSet, commitment, "commitment mismatch");
        assertEq(epochSet, epoch, "epoch mismatch");
        assertFalse(revealedSet, "revealed mismatch");
    }

    function test_CommitAfterCommitmentPeriod(uint256 time) public {
        time = bound(time, defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration, type(uint256).max);
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.commit(0);
    }

    function test_CommitNotAStaker(address caller) public {
        vm.prank(caller);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration());
        vm.expectRevert(IStaking.NotActiveStaker.selector);
        staking.commit(0);
    }

    function test_Reveal(uint192 epochNum, uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        staking.setEpoch(epochNum);
        vm.warp(time);
        vm.prank(executor);
        staking.reveal(sig);

        (,, bool revealed) = staking.commitmentMap(executor);
        assertTrue(revealed, "not revealed");
    }

    function test_RevealBeforeRevealPhase(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration - 1);
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.reveal(abi.encode(0));
    }

    function test_RevealAfterRevealPhase(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - staking.getEpochDuration() + staking.getSelectionPhaseDuration(),
            type(uint256).max
        );
        vm.prank(executor);
        staking.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.reveal(abi.encode(0));
    }

    function test_RevealWrongSigLength(uint192 epochNum) public {
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);
        bytes memory sigExtra = abi.encodePacked(sig, uint8(1));

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sigExtra)), epoch: epochNum, revealed: false}),
            executor
        );

        staking.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidSignatureLength.selector);
        staking.reveal(sigExtra);
    }

    function test_RevealWrongSigner(uint192 epochNum, address caller) public {
        vm.assume(executor != caller);

        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        staking.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(caller);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(sig);
    }

    function test_RevealWrongEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        staking.setEpoch(secondEpochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, secondExecutorPrivateKey));
    }

    function test_RevealWrongChainId(uint192 epochNum, uint256 chainId) public {
        vm.assume(block.chainid != chainId);

        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        staking.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealWrongCommitment(uint192 epochNum, bytes32 commitment) public {
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        vm.assume(commitment != keccak256(abi.encodePacked(sig)));

        staking.setCommitment(IStaking.CommitData({commitment: commitment, epoch: epochNum, revealed: false}), executor);

        staking.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.WrongCommitment.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealCommitmentOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: secondEpochNum, revealed: false}),
            executor
        );

        staking.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.OldEpoch.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealAlreadyRevealed(uint192 epoch) public {
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epoch, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epoch, revealed: true}), executor
        );

        staking.setEpoch(epoch);
        vm.warp(defaultEpochEndTime - staking.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IStaking.CommitmentRevealed.selector);
        staking.reveal(sig);
    }

    function test_SlashCommitter(address slasher, uint256 time) public {
        vm.assume(slasher != executor);
        vm.assume(slasher != address(staking));
        time = bound(time, defaultEpochEndTime, defaultEpochEndTime + staking.getSlashingDuration() - 1);
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.warp(time);
        vm.prank(slasher);
        staking.slashCommitter(executor);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);

        (,, bool revealed) = staking.commitmentMap(executor);
        (uint256 balance, bool active,,,) = staking.stakerInfo(executor);
        assertEq(balance, stakingAmount - commitSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(endBalanceSlasher, startBalanceSlasher + commitSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashCommitterBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - 1);
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.slashCommitter(executor);
    }

    function test_SlashCommitterAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + staking.getSlashingDuration(), type(uint192).max);
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IStaking.InvalidBlockTime.selector);
        staking.slashCommitter(executor);
    }

    function test_SlashCommitterOldEpoch(address slasher, uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: secondEpochNum, revealed: false}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        staking.setEpoch(epochNum);
        vm.prank(slasher);
        vm.warp(defaultEpochEndTime);
        vm.expectRevert(IStaking.OldEpoch.selector);
        staking.slashCommitter(executor);
    }

    function test_SlashCommitterCommitmentRevealed(address slasher) public {
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: true}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.prank(slasher);
        vm.warp(defaultEpochEndTime);
        vm.expectRevert(IStaking.CommitmentRevealed.selector);
        staking.slashCommitter(executor);
    }
}
