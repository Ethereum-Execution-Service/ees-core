// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockCoordinator} from "./mocks/MockCoordinator.sol";
import {StdUtils} from "forge-std/src/StdUtils.sol";
import {ICoordinator} from "../src/interfaces/ICoordinator.sol";
import {SignatureGenerator} from "./utils/SignatureGenerator.sol";
import {DummyJobRegistry} from "./mocks/dummyContracts/DummyJobRegistry.sol";

contract CoordinatorTest is Test, TokenProvider, SignatureGenerator, GasSnapshot {
    MockCoordinator coordinator;
    DummyJobRegistry jobRegistry;

    address defaultStakingToken;
    // same as executor
    address executor;
    uint256 executorPrivateKey;

    address secondExecutor;
    uint256 secondExecutorPrivateKey;

    address thirdExecutor;
    uint256 thirdExecutorPrivateKey;

    uint256 stakingAmount = 1000;
    uint256 stakingBalanceThreshold = 300;
    uint256 minimumStakingPeriod = 2;
    uint256 inactiveSlashingAmount = 200;
    uint256 commitSlashingAmount = 50;
    uint8 roundDuration = 15;
    uint8 roundsPerEpoch = 5;
    uint8 roundBuffer = 15;
    uint8 commitPhaseDuration = 15;
    uint8 revealPhaseDuration = 15;
    uint8 slashingDuration = 30;
    uint256 executorTax = 2;
    uint256 protocolTax = 2;

    uint256 defaultEpochEndTime = 1000;

    address treasury = address(0x3);

    function setUp() public {
        initializeERC20Tokens();
        defaultStakingToken = address(token0);

        ICoordinator.InitSpec memory spec = ICoordinator.InitSpec({
            stakingToken: defaultStakingToken,
            stakingAmount: stakingAmount,
            minimumStakingPeriod: minimumStakingPeriod,
            stakingBalanceThreshold: stakingBalanceThreshold,
            inactiveSlashingAmount: inactiveSlashingAmount,
            commitSlashingAmount: commitSlashingAmount,
            roundDuration: roundDuration,
            roundsPerEpoch: roundsPerEpoch,
            roundBuffer: roundBuffer,
            commitPhaseDuration: commitPhaseDuration,
            revealPhaseDuration: revealPhaseDuration,
            slashingDuration: slashingDuration,
            executorTax: executorTax,
            protocolTax: protocolTax
        });
        coordinator = new MockCoordinator(spec, treasury);
        jobRegistry = new DummyJobRegistry();
        vm.prank(treasury);
        coordinator.setJobRegistry(address(jobRegistry));
        coordinator.setEpochEndTime(defaultEpochEndTime);

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        secondExecutorPrivateKey = 0x43214321;
        secondExecutor = vm.addr(secondExecutorPrivateKey);

        thirdExecutorPrivateKey = 0x11111111;
        thirdExecutor = vm.addr(thirdExecutorPrivateKey);

        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(coordinator));
        setERC20TestTokens(secondExecutor);
        setERC20TestTokenApprovals(vm, secondExecutor, address(coordinator));
        setERC20TestTokens(thirdExecutor);
        setERC20TestTokenApprovals(vm, thirdExecutor, address(coordinator));
        setERC20TestTokens(address(coordinator));
    }

    function test_ExecuteBatchInEpochOutsideRound(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );

        uint256 timeIntoRounds =
            coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() >= roundDuration);

        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,,,,) = coordinator.executorInfo(executor);

        assertEq(failedJobs.length, 0, "number of failed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchNotSelectedExecutor(bytes32 seed) public {
        // first executor is selected for round 0
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);
        vm.prank(executor);
        coordinator.stake();
        vm.prank(secondExecutor);
        coordinator.stake();

        coordinator.setSeed(seed);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(secondExecutor);
        vm.expectRevert(ICoordinator.ExecutorNotSelectedForRound.selector);
        coordinator.executeBatch(indices, gasLimits, secondExecutor);
    }

    function test_ExecuteBatchInRoundCheckIn(uint256 epochPoolBalance) public {
        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        coordinator.setEpoch(10);
        coordinator.setEpochPoolBalance(epochPoolBalance);

        uint256 prevPoolBalance = coordinator.getEpochPoolBalance();

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,, uint8 lastCheckinRound, uint192 lastCheckinEpoch,) = coordinator.executorInfo(executor);
        uint256 newPoolBalance = coordinator.getEpochPoolBalance();
        assertEq(newPoolBalance, prevPoolBalance - prevPoolBalance / roundsPerEpoch);

        assertEq(failedJobs.length, 0, "number of failed jobs mismatch");
        assertEq(balance, stakingAmount + (prevPoolBalance - newPoolBalance) - protocolTax, "executor balance mismatch");
        assertEq(lastCheckinEpoch, 10, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchAlreadyCheckedIn(uint256 time) public {
        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        coordinator.setEpoch(10);
        coordinator.setEpochPoolBalance(100);

        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingAmount,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 10,
                lastCheckinRound: 0,
                stakingTimestamp: block.timestamp
            }),
            executor
        );

        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration());
        vm.prank(executor);
        coordinator.executeBatch(indices, gasLimits, executor);
    }

    function test_ExecuteBatchInRoundNoCheckIn(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - coordinator.getSlashingDuration() - 1
        );
        uint256 timeIntoRounds =
            coordinator.getEpochDuration() - coordinator.getSelectionPhaseDuration() - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % coordinator.getTotalRoundDuration() < roundDuration);

        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,,,,) = coordinator.executorInfo(executor);

        assertEq(failedJobs.length, 0, "number of failed jobs mismatch");
        assertEq(balance, stakingAmount - protocolTax, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchExecutionReverts() public {
        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        jobRegistry.setRevertOnExecute(true);

        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,,,,) = coordinator.executorInfo(executor);

        assertEq(failedJobs.length, 1, "number of failed jobs mismatch");
        assertEq(failedJobs[0], 0, "failed job mismatch");
        assertEq(balance, stakingAmount, "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchBeforeRounds(uint256 time) public {
        time = bound(
            time, 0, defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,,,,) = coordinator.executorInfo(executor);

        assertEq(failedJobs.length, 0, "number of failed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchAfterRounds(uint256 time) public {
        time = bound(time, defaultEpochEndTime, type(uint192).max);
        vm.prank(executor);
        coordinator.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256[] memory failedJobs = coordinator.executeBatch(indices, gasLimits, executor);
        (uint256 balance,,,,,,) = coordinator.executorInfo(executor);

        assertEq(failedJobs.length, 0, "number of failed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(coordinator.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchNotActiveExecutor() public {
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;
        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.executeBatch(indices, gasLimits, executor);
    }

    function test_Stake(uint256 time) public {
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );

        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);
        vm.warp(time);
        coordinator.stake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));

        (
            uint256 balance,
            bool active,
            bool initialized,
            uint40 arrayIndex,
            uint8 lastCheckinRound,
            uint192 lastCheckinEpoch,
            uint256 stakingTimestamp
        ) = coordinator.executorInfo(executor);
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
        assertEq(balance, stakingAmount, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(coordinator.activeExecutors(0), executor, "not in activeExecutors array");
        assertEq(startBalanceExecutor - endBalanceExecutor, stakingAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol - startBalanceProtocol, stakingAmount, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
        assertEq(stakingTimestamp, time, "staking timestamp mismatch");
    }

    function test_StakeInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );
        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.stake();
    }

    function test_StakeArrayNotFull0() public {
        vm.prank(executor);
        coordinator.stake();
        vm.prank(secondExecutor);
        coordinator.stake();

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        coordinator.unstake();
        vm.prank(thirdExecutor);
        coordinator.stake();

        assertEq(coordinator.activeExecutors(0), secondExecutor, "0th index mismatch");
        assertEq(coordinator.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(coordinator.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakeArrayNotFull1() public {
        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(secondExecutor);
        coordinator.unstake();

        vm.prank(thirdExecutor);
        coordinator.stake();

        assertEq(coordinator.activeExecutors(0), executor, "0th index mismatch");
        assertEq(coordinator.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(coordinator.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakingWhenAlreadyStaked() public {
        vm.prank(executor);
        coordinator.stake();
        vm.prank(executor);
        vm.expectRevert(ICoordinator.AlreadyStaked.selector);
        coordinator.stake();
    }

    function test_UnstakeActiveExecutor(uint192 time) public {
        vm.assume(time > minimumStakingPeriod);
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);
        coordinator.stake();

        coordinator.setStakingTimestamp(time - minimumStakingPeriod, executor);

        vm.warp(time);
        vm.prank(executor);
        coordinator.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));

        (
            uint256 balance,
            bool active,
            bool initialized,
            uint40 arrayIndex,
            uint8 lastCheckinRound,
            uint192 lastCheckinEpoch,
            uint256 stakingTimestamp
        ) = coordinator.executorInfo(executor);
        assertFalse(active, "active");
        assertFalse(initialized, "initialized");
        assertEq(balance, 0, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(coordinator.activeExecutors(0), address(0), "in activeExecutors array");
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 0, "number of active executors mismatch");
        assertEq(stakingTimestamp, 0, "staking timestamp mismatch");
    }

    function test_UnstakeBeforeMinimumStakingPeriod(uint192 time) public {
        vm.assume(time > 1);
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );

        vm.warp(time - 1);
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.MinimumStakingPeriodNotOver.selector);
        coordinator.unstake();
    }

    function test_UnstakeInactiveExecutor() public {
        // should not modify activeExecutors array when unstaking an inactive executor
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.prank(executor);

        coordinator.stake();
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingAmount,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                stakingTimestamp: 0
            }),
            executor
        );

        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        coordinator.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(coordinator.activeExecutors(0), executor, "in active executors array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeInvalidBlockTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - 1
        );
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.unstake();
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        vm.warp(defaultEpochEndTime + coordinator.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.unstake();
    }

    function test_TopupToAboveThreshold(uint256 time, uint256 topUpAmount, uint256 startingBalance) public {
        // should activate executor when balance after topup is above coordinator amount
        vm.assume(
            time < defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + coordinator.getSlashingDuration()
        );
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, stakingAmount - startingBalance, token0.balanceOf(executor));
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                stakingTimestamp: 0
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(coordinator));
        vm.warp(time);
        vm.prank(executor);
        coordinator.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(coordinator));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,,) = coordinator.executorInfo(executor);
        assertTrue(active, "not active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_TopupToBelowThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should not activate executor when balance after topup is below coordinator amount
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, 0, stakingAmount - startingBalance - 1);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                stakingTimestamp: 0
            }),
            executor
        );
        vm.prank(executor);
        vm.expectRevert(ICoordinator.TopupBelowMinimum.selector);
        coordinator.topup(topUpAmount);
    }

    function test_TopupNotAnExecutor() public {
        // should revert if not a executor
        vm.prank(executor);
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.topup(stakingAmount);
    }

    function test_TopupInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.topup(stakingAmount);
    }

    function test_InactiveSlashing(address slasher, uint256 time, bytes32 seed) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);

        vm.prank(executor);
        coordinator.stake();

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake();

        (uint256 startBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(1);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
        (uint256 endBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmount - inactiveSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher, uint40 epoch, bytes32 seed) public {
        // should revert with RoundExecuted if round was executed
        vm.assume(slasher != executor);
        vm.prank(executor);
        coordinator.stake();

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake();

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(epoch);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: epoch,
                lastCheckinRound: 0,
                stakingTimestamp: 0
            }),
            executor
        );

        vm.prank(slasher);
        vm.expectRevert(ICoordinator.RoundExecuted.selector);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
    }

    function test_SlashingEndBalanceBelowThreshold(address slasher, bytes32 seed) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        vm.prank(executor);
        coordinator.stake();

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake();

        // assume executor is selected for round 0
        coordinator.setSeed(seed);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);

        coordinator.setEpoch(1);
        coordinator.setExecutorInfo(
            ICoordinator.Executor({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0,
                stakingTimestamp: 0
            }),
            executor
        );
        (uint256 startBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);
        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.prank(slasher);
        coordinator.slashInactiveExecutor(executor, 0, slasher);
        (uint256 endBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingBalanceThreshold + 1 - inactiveSlashingAmount, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
        assertEq(coordinator.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_SlashingBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - coordinator.getSlashingDuration() - 1);

        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashInactiveExecutor(executor, 0, secondExecutor);
    }

    function test_SlashingAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);

        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashInactiveExecutor(executor, 0, secondExecutor);
    }

    function test_SlashingNotSelectedExecutor(bytes32 seed, uint8 round, uint40 numOfactiveExecutors) public {
        // should revert with ExecutorNotSelectedForRound if executor was not selected for round
        vm.assume(numOfactiveExecutors > 0);
        round = uint8(bound(round, 0, roundsPerEpoch - 1));
        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        coordinator.setSeed(seed);
        coordinator.setNumberOfActiveExecutors(numOfactiveExecutors);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, round))) % uint256(numOfactiveExecutors) != 0);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(ICoordinator.ExecutorNotSelectedForRound.selector);
        coordinator.slashInactiveExecutor(executor, round, secondExecutor);
    }

    function test_SlashingRoundExceedingTotal(uint8 round) public {
        round = uint8(bound(round, roundsPerEpoch, type(uint8).max));

        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.RoundExceedingTotal.selector);
        coordinator.slashInactiveExecutor(executor, round, secondExecutor);
    }

    function test_InitiateEpoch(address caller, uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);
        // should increase epochEndTime and increment epoch. Callable by anyone. Should set executedRounds to all false
        coordinator.setEpoch(0);
        vm.warp(time);
        vm.prank(caller);
        coordinator.initiateEpoch();
        assertEq(coordinator.epochEndTime(), time + coordinator.getEpochDuration(), "epoch mismatch");
        assertEq(coordinator.epoch(), 1, "epoch mismatch");
    }

    function test_InitiateBeforeTime(address caller, uint256 time) public {
        // should revert with EpochNotEnded if epochEndTime is not reached
        time = bound(time, 0, defaultEpochEndTime - 1);
        vm.warp(time);
        vm.prank(caller);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.initiateEpoch();
    }

    function test_Commit(bytes32 commitment, uint192 epoch, uint256 time) public {
        // should go from defaultEpochEndTime - coordinator.getEpochDuration() to defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration(),
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration - 1
        );
        vm.prank(executor);
        coordinator.stake();

        coordinator.setEpoch(epoch);
        vm.warp(time);
        vm.prank(executor);
        coordinator.commit(commitment);

        (bytes32 commitmentSet, uint192 epochSet, bool revealedSet) = coordinator.commitmentMap(executor);
        assertEq(commitmentSet, commitment, "commitment mismatch");
        assertEq(epochSet, epoch, "epoch mismatch");
        assertFalse(revealedSet, "revealed mismatch");
    }

    function test_CommitAfterCommitmentPeriod(uint256 time) public {
        time =
            bound(time, defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration, type(uint256).max);
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.commit(0);
    }

    function test_CommitNotAnExecutor(address caller) public {
        vm.prank(caller);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration());
        vm.expectRevert(ICoordinator.NotActiveExecutor.selector);
        coordinator.commit(0);
    }

    function test_Reveal(uint192 epochNum, uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(time);
        vm.prank(executor);
        coordinator.reveal(sig);

        (,, bool revealed) = coordinator.commitmentMap(executor);
        assertTrue(revealed, "not revealed");
    }

    function test_RevealBeforeRevealPhase(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration - 1);
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.reveal(abi.encode(0));
    }

    function test_RevealAfterRevealPhase(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            type(uint256).max
        );
        vm.prank(executor);
        coordinator.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.reveal(abi.encode(0));
    }

    function test_RevealWrongSigLength(uint192 epochNum) public {
        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);
        bytes memory sigExtra = abi.encodePacked(sig, uint8(1));

        coordinator.setCommitment(
            ICoordinator.CommitData({
                commitment: keccak256(abi.encodePacked(sigExtra)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignatureLength.selector);
        coordinator.reveal(sigExtra);
    }

    function test_RevealWrongSigner(uint192 epochNum, address caller) public {
        vm.assume(executor != caller);

        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(caller);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(sig);
    }

    function test_RevealWrongEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(secondEpochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, secondExecutorPrivateKey));
    }

    function test_RevealWrongChainId(uint192 epochNum, uint256 chainId) public {
        vm.assume(block.chainid != chainId);

        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealWrongCommitment(uint192 epochNum, bytes32 commitment) public {
        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        vm.assume(commitment != keccak256(abi.encodePacked(sig)));

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: commitment, epoch: epochNum, revealed: false}), executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.WrongCommitment.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealCommitmentOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: secondEpochNum,
                revealed: false
            }),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.OldEpoch.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealAlreadyRevealed(uint192 epoch) public {
        vm.prank(executor);
        coordinator.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epoch, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epoch, revealed: true}),
            executor
        );

        coordinator.setEpoch(epoch);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.CommitmentRevealed.selector);
        coordinator.reveal(sig);
    }

    function test_SlashCommitter(address slasher, uint256 time) public {
        vm.assume(slasher != executor);
        vm.assume(slasher != address(coordinator));
        time = bound(time, defaultEpochEndTime - coordinator.getSlashingDuration(), defaultEpochEndTime - 1);
        vm.prank(executor);
        coordinator.stake();

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake();

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        (uint256 startBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);

        vm.warp(time);
        vm.prank(slasher);
        coordinator.slashCommitter(executor, slasher);
        (uint256 endBalanceSlasher,,,,,,) = coordinator.executorInfo(slasher);

        (,, bool revealed) = coordinator.commitmentMap(executor);
        (uint256 balance, bool active,,,,,) = coordinator.executorInfo(executor);
        assertEq(balance, stakingAmount - commitSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(endBalanceSlasher, startBalanceSlasher + commitSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashCommitterBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - coordinator.getSlashingDuration() - 1);
        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + coordinator.getSlashingDuration(), type(uint192).max);
        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: false}), executor);

        vm.warp(time);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);
        vm.prank(executor);
        coordinator.stake();

        vm.prank(secondExecutor);
        coordinator.stake();

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: 0, epoch: secondEpochNum, revealed: false}), executor
        );

        coordinator.setEpoch(epochNum);

        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.OldEpoch.selector);
        coordinator.slashCommitter(executor, secondExecutor);
    }

    function test_SlashCommitterCommitmentRevealed(address slasher) public {
        vm.assume(slasher != executor);
        vm.prank(executor);
        coordinator.stake();

        setERC20TestTokens(slasher);
        setERC20TestTokenApprovals(vm, slasher, address(coordinator));
        vm.prank(slasher);
        coordinator.stake();

        coordinator.setCommitment(ICoordinator.CommitData({commitment: 0, epoch: 0, revealed: true}), executor);

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.prank(slasher);
        vm.warp(defaultEpochEndTime - coordinator.getSlashingDuration());
        vm.expectRevert(ICoordinator.CommitmentRevealed.selector);
        coordinator.slashCommitter(executor, slasher);
    }
}
