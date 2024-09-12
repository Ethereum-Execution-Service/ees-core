// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {StdUtils} from "forge-std/src/StdUtils.sol";
import {IStaking} from "../src/interfaces/IStaking.sol";

contract StakingTest is Test, TokenProvider, GasSnapshot {
    MockStaking staking;

    address defaultStakingToken;
    // same as staker
    address executor;
    uint256 executorPrivateKey;

    address secondExecutor;
    uint256 secondExecutorPrivateKey;

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
            slashingWindow: 5,
            roundBuffer: 3,
            epochBuffer: 10
        });
        staking = new MockStaking(spec, 0, address(0x3));

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        secondExecutorPrivateKey = 0x43214321;
        secondExecutor = vm.addr(secondExecutorPrivateKey);
        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(staking));
        setERC20TestTokens(secondExecutor);
        setERC20TestTokenApprovals(vm, secondExecutor, address(staking));
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

        vm.prank(executor);
        vm.roll(1000);
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
        vm.prank(executor);
        vm.roll(1000);
        staking.unstake();
        uint256 endBalanceExecutor = token0.balanceOf(executor);
        uint256 endBalanceProtocol = token0.balanceOf(address(staking));
        assertEq(endBalanceExecutor, startBalanceExecutor, "executor balance mismatch");
        assertEq(staking.activeStakers(0), executor, "in active stakers array");
        assertEq(endBalanceProtocol, startBalanceProtocol, "protocol balance mismatch");
    }

    function test_UnstakeNotInitializedStaked() public {
        // should revert if
        vm.roll(1000);
        vm.prank(executor);
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
        vm.prank(executor);
        staking.stake();
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        staking.setSelectedIndex(0, 0);
        staking.setExecutedRound(0, false);
        staking.setEpochEndBlock(1000);
        vm.roll(1001);
        vm.prank(slasher);
        staking.slash(0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertEq(balance, 800, "balance mismatch");
        assertTrue(active, "not active");
        assertEq(endBalanceSlasher, startBalanceSlasher + 100, "slasher balance mismatch");
    }

    function test_SlashingRoundExecuted(address slasher) public {
        // should revert with RoundExecuted if round was executed
        staking.setSelectedIndex(0, 0);
        staking.setExecutedRound(0, true);
        staking.setEpochEndBlock(1000);
        vm.roll(1001);
        vm.prank(slasher);
        vm.expectRevert(IStaking.RoundExecuted.selector);
        staking.slash(0);
    }

    function test_SlashingBalanceBelowThreshold(address slasher) public {
        // should slash staker balance and slasher should receive half of slashed amount. Staker should still be active in this case
        vm.prank(executor);
        staking.stake();
        staking.setStakerInfo(
            IStaking.StakerInfo({balance: 301, active: true, initialized: true, arrayIndex: 0}), executor
        );
        uint256 startBalanceSlasher = token0.balanceOf(slasher);
        staking.setSelectedIndex(0, 0);
        staking.setExecutedRound(0, false);
        staking.setEpochEndBlock(1000);
        vm.roll(1001);
        vm.prank(slasher);
        staking.slash(0);
        uint256 endBalanceSlasher = token0.balanceOf(slasher);
        (uint256 balance, bool active, bool initialized, uint40 arrayIndex) = staking.stakerInfo(executor);
        assertEq(balance, 101, "balance mismatch");
        assertFalse(active, "active");
        assertEq(endBalanceSlasher, startBalanceSlasher + 100, "slasher balance mismatch");
    }
}
