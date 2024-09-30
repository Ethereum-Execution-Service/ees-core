// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockExecutionManager} from "./mocks/MockExecutionManager.sol";
import {StdUtils} from "forge-std/src/StdUtils.sol";
import {IExecutionManager} from "../src/interfaces/IExecutionManager.sol";
import {SignatureGenerator} from "./utils/SignatureGenerator.sol";
import {DummyJobRegistry} from "./mocks/dummyContracts/DummyJobRegistry.sol";

contract ExecutionManagerTest is Test, TokenProvider, SignatureGenerator, GasSnapshot {
    MockExecutionManager executionManager;
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

        IExecutionManager.InitSpec memory spec = IExecutionManager.InitSpec({
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
            slashingDuration: slashingDuration,
            executorTax: executorTax,
            protocolTax: protocolTax
        });
        executionManager = new MockExecutionManager(spec, treasury);
        jobRegistry = new DummyJobRegistry();
        vm.prank(treasury);
        executionManager.setJobRegistry(address(jobRegistry));
        executionManager.setEpochEndTime(defaultEpochEndTime);

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        secondExecutorPrivateKey = 0x43214321;
        secondExecutor = vm.addr(secondExecutorPrivateKey);

        thirdExecutorPrivateKey = 0x11111111;
        thirdExecutor = vm.addr(thirdExecutorPrivateKey);

        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(executionManager));
        setERC20TestTokens(secondExecutor);
        setERC20TestTokenApprovals(vm, secondExecutor, address(executionManager));
        setERC20TestTokens(thirdExecutor);
        setERC20TestTokenApprovals(vm, thirdExecutor, address(executionManager));
        setERC20TestTokens(address(executionManager));
    }

    function test_ExecuteBatchInEpochOutsideRound(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );

        uint256 timeIntoRounds = executionManager.getEpochDuration() - executionManager.getSelectionPhaseDuration()
            - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % executionManager.getTotalRoundDuration() >= roundDuration);

        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, false);
        (uint256 balance,,,,,) = executionManager.executorInfo(executor);

        assertEq(numberOfExecutedJobs, 1, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchNotSelectedExecutor(bytes32 seed) public {
        // first executor is selected for round 0
        vm.assume(uint256(keccak256(abi.encodePacked(seed, uint8(0)))) % 2 == 0);
        vm.prank(executor);
        executionManager.stake();
        vm.prank(secondExecutor);
        executionManager.stake();

        executionManager.setSeed(seed);

        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration()
        );
        vm.prank(secondExecutor);
        vm.expectRevert(IExecutionManager.ExecutorNotSelectedForRound.selector);
        executionManager.executeBatch(indices, gasLimits, secondExecutor, false);
    }

    function test_ExecuteBatchInRoundCheckIn(uint256 epochPoolBalance) public {
        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        executionManager.setEpoch(10);
        executionManager.setEpochPoolBalance(epochPoolBalance);

        uint256 prevPoolBalance = executionManager.getEpochPoolBalance();

        vm.warp(
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration()
        );
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, true);
        (uint256 balance,,,, uint8 lastCheckinRound, uint192 lastCheckinEpoch) = executionManager.executorInfo(executor);
        uint256 newPoolBalance = executionManager.getEpochPoolBalance();
        assertEq(newPoolBalance, prevPoolBalance - prevPoolBalance / roundsPerEpoch);

        assertEq(numberOfExecutedJobs, 1, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount + (prevPoolBalance - newPoolBalance) - protocolTax, "executor balance mismatch");
        assertEq(lastCheckinEpoch, 10, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchAlreadyCheckedIn(uint256 time) public {
        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        executionManager.setEpoch(10);
        executionManager.setEpochPoolBalance(100);

        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: stakingAmount,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 10,
                lastCheckinRound: 0
            }),
            executor
        );

        vm.warp(
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration()
        );
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.AlreadyCheckedIn.selector);
        executionManager.executeBatch(indices, gasLimits, executor, true);
    }

    function test_ExecuteBatchInRoundNoCheckIn(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration(),
            defaultEpochEndTime - 1
        );
        uint256 timeIntoRounds = executionManager.getEpochDuration() - executionManager.getSelectionPhaseDuration()
            - (defaultEpochEndTime - time);
        vm.assume(timeIntoRounds % executionManager.getTotalRoundDuration() < roundDuration);

        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, false);
        (uint256 balance,,,,,) = executionManager.executorInfo(executor);

        assertEq(numberOfExecutedJobs, 1, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount - protocolTax, "executor balance mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchExecutionReverts() public {
        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        jobRegistry.setRevertOnExecute(true);

        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, false);
        (uint256 balance,,,,,) = executionManager.executorInfo(executor);

        assertEq(numberOfExecutedJobs, 0, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount, "executor balance mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), 0, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchBeforeRounds(uint256 time) public {
        time = bound(
            time,
            0,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, false);
        (uint256 balance,,,,,) = executionManager.executorInfo(executor);

        assertEq(numberOfExecutedJobs, 1, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchAfterRounds(uint256 time) public {
        time = bound(time, defaultEpochEndTime, type(uint192).max);
        vm.prank(executor);
        executionManager.stake();
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;

        vm.warp(time);
        vm.prank(executor);
        uint256 numberOfExecutedJobs = executionManager.executeBatch(indices, gasLimits, executor, false);
        (uint256 balance,,,,,) = executionManager.executorInfo(executor);

        assertEq(numberOfExecutedJobs, 1, "number of executed jobs mismatch");
        assertEq(balance, stakingAmount - (executorTax + protocolTax), "executor balance mismatch");
        assertEq(executionManager.getNextEpochPoolBalance(), executorTax, "next epoch pool balance mismatch");
    }

    function test_ExecuteBatchNotActiveExecutor() public {
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        uint256[] memory gasLimits = new uint256[](1);
        gasLimits[0] = 500_000;
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.NotActiveExecutor.selector);
        executionManager.executeBatch(indices, gasLimits, executor, false);
    }

    function test_Stake(uint256 time) public {
        vm.assume(
            time
                < defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + executionManager.getSlashingDuration()
        );

        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(executionManager));
        vm.prank(executor);
        vm.warp(time);
        executionManager.stake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(executionManager));

        (
            uint256 balance,
            bool active,
            bool initialized,
            uint40 arrayIndex,
            uint8 lastCheckinRound,
            uint192 lastCheckinEpoch
        ) = executionManager.executorInfo(executor);
        assertTrue(active, "not active");
        assertTrue(initialized, "not initialized");
        assertEq(balance, stakingAmount, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(executionManager.activeExecutors(0), executor, "not in activeExecutors array");
        assertEq(startBalanceExecutor - endBalanceExecutor, stakingAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol - startBalanceProtocol, stakingAmount, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(executionManager.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_StakeInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration(),
            defaultEpochEndTime + executionManager.getSlashingDuration() - 1
        );
        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.stake();
    }

    function test_StakeArrayNotFull0() public {
        vm.prank(executor);
        executionManager.stake();
        vm.prank(secondExecutor);
        executionManager.stake();

        vm.warp(defaultEpochEndTime + executionManager.getSlashingDuration());
        vm.prank(executor);
        executionManager.unstake();
        vm.prank(thirdExecutor);
        executionManager.stake();

        assertEq(executionManager.activeExecutors(0), secondExecutor, "0th index mismatch");
        assertEq(executionManager.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(executionManager.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakeArrayNotFull1() public {
        vm.prank(executor);
        executionManager.stake();

        vm.prank(secondExecutor);
        executionManager.stake();

        vm.warp(defaultEpochEndTime + executionManager.getSlashingDuration());
        vm.prank(secondExecutor);
        executionManager.unstake();

        vm.prank(thirdExecutor);
        executionManager.stake();

        assertEq(executionManager.activeExecutors(0), executor, "0th index mismatch");
        assertEq(executionManager.activeExecutors(1), thirdExecutor, "1st index mismatch");
        assertEq(executionManager.getActiveExecutorsLength(), 2, "array length mismatch");
    }

    function test_StakingWhenAlreadyStaked() public {
        vm.prank(executor);
        executionManager.stake();
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.AlreadyStaked.selector);
        executionManager.stake();
    }

    function test_UnstakeActiveExecutor(uint192 time) public {
        vm.assume(
            time < defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration
                || time >= defaultEpochEndTime + executionManager.getSlashingDuration()
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(executionManager));
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        executionManager.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(executionManager));

        (
            uint256 balance,
            bool active,
            bool initialized,
            uint40 arrayIndex,
            uint8 lastCheckinRound,
            uint192 lastCheckinEpoch
        ) = executionManager.executorInfo(executor);
        assertFalse(active, "active");
        assertFalse(initialized, "initialized");
        assertEq(balance, 0, "balance mismatch");
        assertEq(arrayIndex, 0, "array index mismatch");
        assertEq(executionManager.activeExecutors(0), address(0), "in activeExecutors array");
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
        assertEq(lastCheckinEpoch, 0, "latest executed epoch mismatch");
        assertEq(lastCheckinRound, 0, "latest executed round mismatch");
        assertEq(executionManager.getNumberOfActiveExecutors(), 0, "number of active executors mismatch");
    }

    function test_UnstakeInactiveExecutor() public {
        // should not modify activeExecutors array when unstaking an inactive executor
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(executionManager));
        vm.prank(executor);

        executionManager.stake();
        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: stakingAmount,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0
            }),
            executor
        );

        vm.warp(defaultEpochEndTime + executionManager.getSlashingDuration());
        vm.prank(executor);
        executionManager.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(executionManager));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(executionManager.activeExecutors(0), executor, "in active executors array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeInvalidBlockTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime + executionManager.getSlashingDuration() - 1
        );
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.unstake();
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        vm.warp(defaultEpochEndTime + executionManager.getSlashingDuration());
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.NotActiveExecutor.selector);
        executionManager.unstake();
    }

    function test_TopupToAboveThreshold(uint256 time, uint256 topUpAmount, uint256 startingBalance) public {
        // should activate executor when balance after topup is above executionManager amount
        vm.assume(
            time
                < defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration()
                || time >= defaultEpochEndTime + executionManager.getSlashingDuration()
        );
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, stakingAmount, token0.balanceOf(executor));
        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(executionManager));
        vm.warp(time);
        vm.prank(executor);
        executionManager.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(executionManager));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,) = executionManager.executorInfo(executor);
        assertTrue(active, "not active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
        assertEq(executionManager.getNumberOfActiveExecutors(), 1, "number of active executors mismatch");
    }

    function test_TopupToBelowThreshold(uint256 topUpAmount, uint256 startingBalance) public {
        // should not activate executor when balance after topup is below executionManager amount
        startingBalance = bound(startingBalance, 0, stakingBalanceThreshold - 1);
        topUpAmount = bound(topUpAmount, 0, stakingAmount - startingBalance - 1);
        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: startingBalance,
                active: false,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0
            }),
            executor
        );
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceProtocol = token0.balanceOf(address(executionManager));
        vm.prank(executor);
        executionManager.topup(topUpAmount);
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(executionManager));

        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,) = executionManager.executorInfo(executor);
        assertFalse(active, "active");
        assertEq(balance, startingBalance + topUpAmount, "balance mismatch");
        assertEq(endBalanceExecutor, startBalanceExecutor - topUpAmount, "executor balance mismatch");
        assertEq(endBalanceProtocol, startBalanceProtocol + topUpAmount, "protocol balance mismatch");
    }

    function test_TopupNotAnExecutor() public {
        // should revert if not a executor
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.NotActiveExecutor.selector);
        executionManager.topup(stakingAmount);
    }

    function test_TopupInvalidTime(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration(),
            defaultEpochEndTime + executionManager.getSlashingDuration() - 1
        );
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.topup(stakingAmount);
    }

    function test_Slashing(address slasher, uint256 time) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(executionManager));
        time = bound(time, defaultEpochEndTime, defaultEpochEndTime + executionManager.getSlashingDuration() - 1);

        vm.prank(executor);
        executionManager.stake();
        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        executionManager.setEpoch(1);

        vm.warp(time);
        vm.prank(slasher);
        executionManager.slashInactiveExecutor(executor, 0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,) = executionManager.executorInfo(executor);
        assertEq(balance, stakingAmount - inactiveSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher, uint40 epoch) public {
        // should revert with RoundExecuted if round was executed
        vm.prank(executor);
        executionManager.stake();
        vm.warp(defaultEpochEndTime);

        executionManager.setEpoch(epoch);
        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: epoch,
                lastCheckinRound: 0
            }),
            executor
        );

        vm.prank(slasher);
        vm.expectRevert(IExecutionManager.RoundExecuted.selector);
        executionManager.slashInactiveExecutor(executor, 0);
    }

    function test_SlashingEndBalanceBelowThreshold(address slasher) public {
        // should slash executor balance and slasher should receive half of slashed amount. Executor should still be active in this case
        vm.assume(slasher != executor);
        vm.assume(slasher != address(executionManager));
        vm.prank(executor);
        executionManager.stake();

        executionManager.setEpoch(1);
        executionManager.setExecutorInfo(
            IExecutionManager.Executor({
                balance: stakingBalanceThreshold + 1,
                active: true,
                initialized: true,
                arrayIndex: 0,
                lastCheckinEpoch: 0,
                lastCheckinRound: 0
            }),
            executor
        );
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        vm.warp(defaultEpochEndTime);
        vm.prank(slasher);
        executionManager.slashInactiveExecutor(executor, 0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex,,) = executionManager.executorInfo(executor);
        assertEq(balance, stakingBalanceThreshold + 1 - inactiveSlashingAmount, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + inactiveSlashingAmount / 2, "slasher balance mismatch");
        assertEq(executionManager.getNumberOfActiveExecutors(), 0, "number of active executors mismatch");
    }

    function test_SlashingBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - 1);

        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.slashInactiveExecutor(executor, 0);
    }

    function test_SlashingAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + executionManager.getSlashingDuration(), type(uint192).max);

        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.slashInactiveExecutor(executor, 0);
    }

    function test_SlashingNotSelectedExecutor(bytes32 seed, uint8 round, uint40 numOfactiveExecutors) public {
        // should revert with ExecutorNotSelectedForRound if executor was not selected for round
        vm.assume(numOfactiveExecutors > 0);
        round = uint8(bound(round, 0, roundsPerEpoch - 1));
        vm.prank(executor);
        executionManager.stake();
        executionManager.setSeed(seed);
        executionManager.setNumberOfActiveExecutors(numOfactiveExecutors);
        vm.assume(uint256(keccak256(abi.encodePacked(seed, round))) % uint256(numOfactiveExecutors) != 0);

        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.ExecutorNotSelectedForRound.selector);
        executionManager.slashInactiveExecutor(executor, round);
    }

    function test_SlashingRoundExceedingTotal(uint8 round) public {
        round = uint8(bound(round, roundsPerEpoch, type(uint8).max));
        vm.warp(defaultEpochEndTime);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.RoundExceedingTotal.selector);
        executionManager.slashInactiveExecutor(executor, round);
    }

    function test_InitiateEpoch(address caller, uint256 time) public {
        time = bound(time, defaultEpochEndTime + executionManager.getSlashingDuration(), type(uint192).max);
        // should increase epochEndTime and increment epoch. Callable by anyone. Should set executedRounds to all false
        executionManager.setEpoch(0);
        vm.warp(time);
        vm.prank(caller);
        executionManager.initiateEpoch();
        assertEq(executionManager.epochEndTime(), time + executionManager.getEpochDuration(), "epoch mismatch");
        assertEq(executionManager.epoch(), 1, "epoch mismatch");
    }

    function test_InitiateBeforeTime(address caller, uint256 time) public {
        // should revert with EpochNotEnded if epochEndTime is not reached
        time = bound(time, 0, defaultEpochEndTime + executionManager.getSlashingDuration() - 1);
        vm.warp(time);
        vm.prank(caller);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.initiateEpoch();
    }

    function test_Commit(bytes32 commitment, uint192 epoch, uint256 time) public {
        // should go from defaultEpochEndTime - executionManager.getEpochDuration() to defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration(),
            defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration - 1
        );
        vm.prank(executor);
        executionManager.stake();

        executionManager.setEpoch(epoch);
        vm.warp(time);
        vm.prank(executor);
        executionManager.commit(commitment);

        (bytes32 commitmentSet, uint192 epochSet, bool revealedSet) = executionManager.commitmentMap(executor);
        assertEq(commitmentSet, commitment, "commitment mismatch");
        assertEq(epochSet, epoch, "epoch mismatch");
        assertFalse(revealedSet, "revealed mismatch");
    }

    function test_CommitAfterCommitmentPeriod(uint256 time) public {
        time = bound(
            time, defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration, type(uint256).max
        );
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.commit(0);
    }

    function test_CommitNotAnExecutor(address caller) public {
        vm.prank(caller);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration());
        vm.expectRevert(IExecutionManager.NotActiveExecutor.selector);
        executionManager.commit(0);
    }

    function test_Reveal(uint192 epochNum, uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(time);
        vm.prank(executor);
        executionManager.reveal(sig);

        (,, bool revealed) = executionManager.commitmentMap(executor);
        assertTrue(revealed, "not revealed");
    }

    function test_RevealBeforeRevealPhase(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration - 1);
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.reveal(abi.encode(0));
    }

    function test_RevealAfterRevealPhase(uint256 time) public {
        time = bound(
            time,
            defaultEpochEndTime - executionManager.getEpochDuration() + executionManager.getSelectionPhaseDuration(),
            type(uint256).max
        );
        vm.prank(executor);
        executionManager.stake();

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.reveal(abi.encode(0));
    }

    function test_RevealWrongSigLength(uint192 epochNum) public {
        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);
        bytes memory sigExtra = abi.encodePacked(sig, uint8(1));

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sigExtra)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidSignatureLength.selector);
        executionManager.reveal(sigExtra);
    }

    function test_RevealWrongSigner(uint192 epochNum, address caller) public {
        vm.assume(executor != caller);

        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(caller);
        vm.expectRevert(IExecutionManager.InvalidSignature.selector);
        executionManager.reveal(sig);
    }

    function test_RevealWrongEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(secondEpochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidSignature.selector);
        executionManager.reveal(generateSignature(ethSignedMessageHash, secondExecutorPrivateKey));
    }

    function test_RevealWrongChainId(uint192 epochNum, uint256 chainId) public {
        vm.assume(block.chainid != chainId);

        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidSignature.selector);
        executionManager.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealWrongCommitment(uint192 epochNum, bytes32 commitment) public {
        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        vm.assume(commitment != keccak256(abi.encodePacked(sig)));

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: commitment, epoch: epochNum, revealed: false}), executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.WrongCommitment.selector);
        executionManager.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealCommitmentOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: secondEpochNum,
                revealed: false
            }),
            executor
        );

        executionManager.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.OldEpoch.selector);
        executionManager.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealAlreadyRevealed(uint192 epoch) public {
        vm.prank(executor);
        executionManager.stake();

        bytes32 msgHash = keccak256(abi.encodePacked(epoch, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epoch, revealed: true}),
            executor
        );

        executionManager.setEpoch(epoch);
        vm.warp(defaultEpochEndTime - executionManager.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.CommitmentRevealed.selector);
        executionManager.reveal(sig);
    }

    function test_SlashCommitter(address slasher, uint256 time) public {
        vm.assume(slasher != executor);
        vm.assume(slasher != address(executionManager));
        time = bound(time, defaultEpochEndTime, defaultEpochEndTime + executionManager.getSlashingDuration() - 1);
        vm.prank(executor);
        executionManager.stake();

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: 0, epoch: 0, revealed: false}), executor
        );

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.warp(time);
        vm.prank(slasher);
        executionManager.slashCommitter(executor);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);

        (,, bool revealed) = executionManager.commitmentMap(executor);
        (uint256 balance, bool active,,,,) = executionManager.executorInfo(executor);
        assertEq(balance, stakingAmount - commitSlashingAmount, "balance mismatch");
        assertTrue(active, "not active");
        assertTrue(revealed, "not revealed");
        assertEq(endBalanceSlasher, startBalanceSlasher + commitSlashingAmount / 2, "slasher balance mismatch");
    }

    function test_SlashCommitterBeforeTime(uint256 time) public {
        time = bound(time, 0, defaultEpochEndTime - 1);
        vm.prank(executor);
        executionManager.stake();

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: 0, epoch: 0, revealed: false}), executor
        );

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.slashCommitter(executor);
    }

    function test_SlashCommitterAfterTime(uint256 time) public {
        time = bound(time, defaultEpochEndTime + executionManager.getSlashingDuration(), type(uint192).max);
        vm.prank(executor);
        executionManager.stake();

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: 0, epoch: 0, revealed: false}), executor
        );

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(IExecutionManager.InvalidBlockTime.selector);
        executionManager.slashCommitter(executor);
    }

    function test_SlashCommitterOldEpoch(address slasher, uint192 epochNum, uint192 secondEpochNum) public {
        vm.assume(epochNum != secondEpochNum);
        vm.prank(executor);
        executionManager.stake();

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: 0, epoch: secondEpochNum, revealed: false}), executor
        );

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        executionManager.setEpoch(epochNum);
        vm.prank(slasher);
        vm.warp(defaultEpochEndTime);
        vm.expectRevert(IExecutionManager.OldEpoch.selector);
        executionManager.slashCommitter(executor);
    }

    function test_SlashCommitterCommitmentRevealed(address slasher) public {
        vm.prank(executor);
        executionManager.stake();

        executionManager.setCommitment(
            IExecutionManager.CommitData({commitment: 0, epoch: 0, revealed: true}), executor
        );

        uint256 startBalanceSlasher = token0.balanceOf(slasher);

        vm.prank(slasher);
        vm.warp(defaultEpochEndTime);
        vm.expectRevert(IExecutionManager.CommitmentRevealed.selector);
        executionManager.slashCommitter(executor);
    }
}
