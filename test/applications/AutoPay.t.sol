// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
import {AutoPay} from "../../src/applications/AutoPay.sol";
import {IAutoPay} from "../../src/interfaces/applications/IAutoPay.sol";

contract AutoPayTest is Test, GasSnapshot {
    AutoPay autoPay;

    address defaultFeeToken = address(0x3);
    uint256 defaultMinExecutionFee;
    uint256 defaultMaxExecutionFee;
    uint32 defaultExecutionWindow;
    uint256 defaultStartTime;

    address from;
    uint256 fromPrivateKey;

    address address0 = address(0x0);
    address address2 = address(0x2);
    JobRegistry jobRegistry;

    function setUp() public {
        defaultMaxExecutionFee = 100;
        defaultMinExecutionFee = 0;
        defaultExecutionWindow = 1800;
        defaultStartTime = 1641070800;

        jobRegistry = new JobRegistry(address2, address2, 2);
        autoPay = new AutoPay(jobRegistry, address2, 3000, address2);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
    }

    function test_FindFactor() public {
        bytes12 amountFactors = 0x0300000001F40303E8054E20;
        uint48 executionNumber = 5;
        uint16 factor = autoPay.findFactor(amountFactors, executionNumber);
        assertEq(factor, 0x4E20, "factor not equal");
    }

    function test_FindFactor2() public {
        bytes12 amountFactors = 0x0200000001F40303E8000000;
        uint48 executionNumber = 4;
        uint16 factor = autoPay.findFactor(amountFactors, executionNumber);
        assertEq(factor, 10000, "factor not equal");
    }

    function test_FindFactor3() public {
        bytes12 amountFactors = 0x0000000001F40303E8000000;
        uint48 executionNumber = 0;
        uint16 factor = autoPay.findFactor(amountFactors, executionNumber);
        assertEq(factor, 10000, "factor not equal");
    }
}
