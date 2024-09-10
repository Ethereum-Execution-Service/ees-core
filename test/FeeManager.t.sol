// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
/*
import {Test} from "forge-std/Test.sol";
import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {AddressBuilder} from "./utils/AddressBuilder.sol";
import {AmountBuilder} from "./utils/AmountBuilder.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";
import {FeeManager} from "../src/FeeManager.sol";

contract FeeManagerTest is Test, TokenProvider, GasSnapshot {
    using AddressBuilder for address[];
    using AmountBuilder for uint256[];

    event Transfer(address indexed from, address indexed token, address indexed to, uint256 amount);

    FeeManager feeManager;

    address from;
    uint256 fromPrivateKey;
    uint256 defaultAmount = 10 * 1e6;

    address address0 = address(0x0);
    address address2 = address(0x2);

    address feeRecipient = address2;
    uint16 feeBasisPoints = 3000;

    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        vm.prank(address0);
        feeManager = new FeeManager(address2, address0, feeBasisPoints);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
    }

    function test_SimpleExample_0() public {
        // 3000 = 0.03%
        (uint256 fee, uint256 remaining) = feeManager.calculateFee(1000, 3000);
        assertEq(fee, 3);
        assertEq(remaining, 997);
    }

    function test_SmallAmount_0() public {
        // 3000 = 0.30%
        (uint256 fee, uint256 remaining) = feeManager.calculateFee(1, 3000);
        assertEq(fee, 0);
        assertEq(remaining, 1);
    }

    function test_SmallAmount_1() public {
        // 1000 = 0.10%
        // BASE_FEE is 1_000_000, so 1001 * 1000 / 1_000_000 = 1
        (uint256 fee, uint256 remaining) = feeManager.calculateFee(1001, 1000);
        assertEq(fee, 1);
        assertEq(remaining, 1000);
    }

    function test_BasePointsZero(uint256 amount) public {
        (uint256 fee, uint256 remaining) = feeManager.calculateFee(amount, 0);
        assertEq(fee, 0);
        assertEq(remaining, amount);
    }

    function test_AmountZero(uint16 basePoints) public {
        (uint256 fee, uint256 remaining) = feeManager.calculateFee(0, basePoints);
        assertEq(fee, 0);
        assertEq(remaining, 0);
    }

    function testFail_NumericOverflow(uint256 amount, uint16 basePoints) public {
        vm.assume(amount * basePoints > type(uint256).max);
        feeManager.calculateFee(amount, basePoints);
    }

    function testFail_NumericOverflowManual() public {
        feeManager.calculateFee(type(uint256).max / 2, 500);
    }
}
    */
