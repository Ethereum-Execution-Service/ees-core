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

    function setUp() public {
        initializeERC20Tokens();
        defaultStakingToken = address(token0);

        IStaking.StakingSpec memory spec = IStaking.StakingSpec({
            stakingToken: defaultStakingToken,
            stakingAmount: 1000,
            stakingBalanceThreshold: 300,
            slashingAmount: 200,
            roundDuration: 5,
            roundsPerEpoch: 10,
            roundBuffer: 5,
            commitPhaseDuration: 5,
            revealPhaseDuration: 5
        });
        staking = new MockStaking(spec);

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

    function test_Stake() public {
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.stake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
        assertEq(balance, 1000, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(staking.activeStakers(0), executor, "not in active stakers array");
        assertEq(startBalanceExecutor - endBalanceExecutor, 1000, "executor balance mismatch");
        assertEq(endBalanceProtocol - startBalanceProtocol, 1000, "protocol balance mismatch");
    }

    function test_StakeArrayNotFull0() public {
        vm.prank(executor);
        staking.stake();
        vm.prank(secondExecutor);
        staking.stake();
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(894);
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

        staking.setEpochEndBlock(1000);
        vm.prank(secondExecutor);
        vm.roll(894);
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

    function test_UnstakeActiveStaker() public {
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.stake();

        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(894);
        staking.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertFalse(active, "active");
        assertFalse(initialized, "initialized");
        assertEq(balance, 0, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(staking.activeStakers(0), address(0), "in active stakers array");
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeInactiveStaker() public {
        // should not modify activeStakers array when unstaking an inactive staker
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);

        staking.stake();
        staking.setStakerInfo(
            IStaking.StakerInfo({balance: 1000, active: false, initialized: true, arrayIndex: 0}), executor
        );
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(894);
        staking.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(staking.activeStakers(0), executor, "in active stakers array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(894);
        vm.expectRevert(IStaking.NotAStaker.selector);
        staking.unstake();
    }

    function test_TopupToAboveThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should activate staker when balance after topup is above staking amount
        startingBalance = bound(startingBalance, 0, 299);
        topUpAmount = bound(topUpAmount, 1000, token0.balanceOf(executor));
        staking.setStakerInfo(
            IStaking.StakerInfo({balance: startingBalance, active: false, initialized: true, arrayIndex: 0}), executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertTrue(active, "not active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
    }

    function test_TopupToBelowThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should not activate staker when balance after topup is below staking amount
        startingBalance = bound(startingBalance, 0, 299);
        topUpAmount = bound(topUpAmount, 0, 1000 - startingBalance - 1);
        staking.setStakerInfo(
            IStaking.StakerInfo({balance: startingBalance, active: false, initialized: true, arrayIndex: 0}), executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(staking));
        vm.prank(executor);
        staking.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertFalse(active, "active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
    }

    function test_TopupNotAStaker() public {
        // should revert if not a staker
        vm.prank(executor);
        vm.expectRevert(IStaking.NotAStaker.selector);
        staking.topup(1000);
    }

    function test_Slashing(address slasher) public {
        // should slash staker balance and slasher should receive half of slashed amount. Staker should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(staking));
        vm.prank(executor);
        staking.stake();
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        staking.setExecutedRound(0, false);
        staking.setEpochEndBlock(1000);
        vm.roll(905);
        vm.prank(slasher);
        staking.slashInactiveStaker();
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertEq(balance, 800, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + 100, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher) public {
        // should revert with RoundExecuted if round was executed
        vm.prank(executor);
        staking.stake();
        staking.setExecutedRound(0, true);
        staking.setEpochEndBlock(1000);
        vm.roll(905);
        vm.prank(slasher);
        vm.expectRevert(IStaking.RoundExecuted.selector);
        staking.slashInactiveStaker();
    }

    function test_SlashingEndBalanceBelowThreshold(address slasher) public {
        // should slash staker balance and slasher should receive half of slashed amount. Staker should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(staking));
        vm.prank(executor);
        staking.stake();
        staking.setStakerInfo(
            IStaking.StakerInfo({balance: 301, active: true, initialized: true, arrayIndex: 0}), executor
        );
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        staking.setExecutedRound(0, false);
        staking.setEpochEndBlock(1000);
        vm.roll(905);
        vm.prank(slasher);
        staking.slashInactiveStaker();
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertEq(balance, 101, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + 100, "slasher balance mismatch");
    }

    function test_InitiateEpoch(address caller) public {
        // should increase epochEndBlock and increment epoch. Callable by anyone. Should set executedRounds to all false
        staking.setEpochEndBlock(1000);
        staking.setExecutedRound(0, true);
        staking.setExecutedRound(1, true);
        staking.setEpoch(0);
        vm.roll(1000);
        vm.prank(caller);
        staking.initiateEpoch();
        assertEq(staking.epochEndBlock(), 1110, "epoch mismatch");
        assertEq(staking.epoch(), 1, "epoch mismatch");
        for (uint256 i = 0; i < staking.numberOfActiveStakers(); i++) {
            assertFalse(staking.executedRounds(0), "executed round mismatch");
        }
    }

    function test_InitiateNewEpochDuringEpoch(address caller, uint256 blockNum) public {
        // should revert with EpochNotEnded if epochEndBlock is not reached
        blockNum = bound(blockNum, 0, 999);
        staking.setEpochEndBlock(1000);
        vm.roll(999);
        vm.prank(caller);
        vm.expectRevert(IStaking.InvalidBlockNumber.selector);
        staking.initiateEpoch();
    }

    function test_Commit(bytes32 commitment, uint256 epoch) public {
        vm.prank(executor);
        staking.stake();

        staking.setEpoch(epoch);
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(894);
        staking.commit(commitment);

        (bytes32 commitmentSet, uint256 epochSet, bool revealedSet) = staking.commitmentMap(executor);
        assertEq(commitmentSet, commitment, "commitment mismatch");
        assertEq(epochSet, epoch, "epoch mismatch");
        assertFalse(revealedSet, "revealed mismatch");
    }

    function test_CommitNotAStaker(address caller, bytes32 commitment) public {
        staking.setEpochEndBlock(1000);
        vm.prank(caller);
        vm.roll(894);
        vm.expectRevert(IStaking.NotAStaker.selector);
        staking.commit(commitment);
    }

    function test_Reveal(uint256 epochNum) public {
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
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        staking.reveal(sig);

        (,, bool revealed) = staking.commitmentMap(executor);
        assertTrue(revealed, "not revealed");
    }

    function test_RevealWrongSigLength(uint256 epochNum) public {
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
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.InvalidSignatureLength.selector);
        staking.reveal(sigExtra);
    }

    function test_RevealWrongSigner(uint256 epochNum, address caller) public {
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
        staking.setEpochEndBlock(1000);
        vm.prank(caller);
        vm.roll(895);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(sig);
    }

    function test_RevealWrongEpoch(uint256 epochNum, uint256 secondEpochNum) public {
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
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, secondExecutorPrivateKey));
    }

    function test_RevealWrongChainId(uint256 epochNum, uint256 chainId) public {
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
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.InvalidSignature.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealWrongCommitment(uint256 epochNum, bytes32 commitment) public {
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        vm.assume(commitment != keccak256(abi.encodePacked(sig)));

        staking.setCommitment(IStaking.CommitData({commitment: commitment, epoch: epochNum, revealed: false}), executor);

        staking.setEpoch(epochNum);
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.WrongCommitment.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealCommitmentOldEpoch(uint256 epochNum, uint256 secondEpochNum) public {
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

        staking.setEpochEndBlock(1000);
        staking.setEpoch(epochNum);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.OldEpoch.selector);
        staking.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealAlreadyRevealed(uint256 epoch) public {
        vm.prank(executor);
        staking.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epoch, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        staking.setCommitment(
            IStaking.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epoch, revealed: true}), executor
        );

        staking.setEpoch(epoch);
        staking.setEpochEndBlock(1000);
        vm.prank(executor);
        vm.roll(895);
        vm.expectRevert(IStaking.CommitmentRevealed.selector);
        staking.reveal(sig);
    }

    function test_SlashCommitter(address slasher) public {
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        staking.setEpochEndBlock(1000);
        vm.prank(slasher);
        vm.roll(900);
        staking.slashCommitter(executor);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);

        (,, bool revealed) = staking.commitmentMap(executor);
        (uint256 balance, bool active,,) = staking.stakerInfo(executor);
        assertEq(balance, 800, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(endBalanceSlasher, startBalanceSlasher + 100, "slasher balance mismatch");
    }

    function test_SlashCommitterOldEpoch(address slasher, uint256 epochNum, uint256 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: secondEpochNum, revealed: false}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        staking.setEpoch(epochNum);
        staking.setEpochEndBlock(1000);
        vm.prank(slasher);
        vm.roll(900);
        vm.expectRevert(IStaking.OldEpoch.selector);
        staking.slashCommitter(executor);
    }

    function test_SlashCommitterCommitmentRevealed(address slasher) public {
        vm.prank(executor);
        staking.stake();

        staking.setCommitment(IStaking.CommitData({commitment: 0, epoch: 0, revealed: true}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        staking.setEpochEndBlock(1000);
        vm.prank(slasher);
        vm.roll(900);
        vm.expectRevert(IStaking.CommitmentRevealed.selector);
        staking.slashCommitter(executor);
    }
}
