// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockFeeManager} from "./mocks/MockFeeManager.sol";
import {StdUtils} from "forge-std/src/StdUtils.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";

contract FeeManagerTest is Test, TokenProvider, GasSnapshot {
    MockFeeManager feeManager;

    address treasury;
    uint256 trasuryPrivateKey;

    address executor;
    uint256 executorPrivateKey;

    uint8 defaultProtocolFeeRatio;

    function setUp() public {
        initializeERC20Tokens();
        defaultProtocolFeeRatio = 2;

        trasuryPrivateKey = 0x12344321;
        treasury = vm.addr(trasuryPrivateKey);

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        feeManager = new MockFeeManager(treasury, defaultProtocolFeeRatio);
    }

    function test_UpdateProtocolFeeRatio(uint8 protocolFeeRatio) public {
        // Should be able to update protocol fee ratio
        vm.prank(treasury);
        feeManager.updateProtocolFeeRatio(protocolFeeRatio);
        assertEq(feeManager.getProtocolFeeRatio(), protocolFeeRatio, "protocol fee ratio mismatch");
    }

    function testFail_UpdateProtocolFeeRatioNotTreasury(address caller) public {
        // Should revert when updating protocol fee ratio from a caller that is not the treasury
        vm.assume(caller != treasury);
        vm.prank(caller);
        feeManager.updateProtocolFeeRatio(1);
    }

    event Hello(uint256 balance);

    function test_WithdrawCollectedFee(address caller, uint256 tokenAmount) public {
        vm.assume(caller != address(feeManager));
        vm.assume(tokenAmount > 0);
        // Should be able to withdraw protocol fee
        uint256 startBalanceCaller = token0.balanceOf(caller);
        deal(address(token0), address(feeManager), tokenAmount);
        uint256 startBalanceFeeManager = token0.balanceOf(address(feeManager));
        feeManager.setFeeBalance(caller, tokenAmount, address(token0));
        vm.prank(caller);
        feeManager.withdrawCollectedFees(address(token0), caller);
        assertEq(token0.balanceOf(caller), startBalanceCaller + tokenAmount, "caller balance mismatch");
        assertEq(
            token0.balanceOf(address(feeManager)), startBalanceFeeManager - tokenAmount, "feeManager balance mismatch"
        );
    }

    function test_WithdrawZeroCollectedFee(address caller) public {
        // Should revert when withdrawing zero protocol fee
        vm.prank(caller);
        vm.expectRevert(IFeeManager.NoFeesToWithdraw.selector);
        feeManager.withdrawCollectedFees(address(token0), caller);
    }
}
