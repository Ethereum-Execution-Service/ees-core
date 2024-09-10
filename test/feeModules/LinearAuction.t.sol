// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
import {ILinearAuction} from "../../src/interfaces/feeModules/ILinearAuction.sol";
import {MockLinearAuction} from "../mocks/MockLinearAuction.sol";

contract LinearAuctionTest is Test, GasSnapshot {
    MockLinearAuction feeModule;

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

    event ExecutionFee(uint256 executionFee);

    function setUp() public {
        defaultMaxExecutionFee = 100;
        defaultMinExecutionFee = 0;
        defaultExecutionWindow = 1800;
        defaultStartTime = 1641070800;

        jobRegistry = new JobRegistry(address2, address2, 2);
        feeModule = new MockLinearAuction(jobRegistry);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
    }

    function test_FeeExample() public {
        uint256 secondsInAuctionPeriod = 900;
        uint256 minExecutionFee = 100000;
        uint256 maxExecutionFee = 200000;
        vm.prank(address(jobRegistry));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, minExecutionFee, maxExecutionFee));
        vm.warp(defaultStartTime + secondsInAuctionPeriod);
        vm.prank(address(jobRegistry));
        (uint256 executionFee,) = feeModule.onExecuteJob(0, from, defaultExecutionWindow, defaultStartTime, 0);
        emit ExecutionFee(executionFee);
    }

    function test_CorrectFeeCalculation(
        uint256 secondsInAuctionPeriod,
        uint256 minExecutionFee,
        uint256 maxExecutionFee
    ) public {
        secondsInAuctionPeriod = bound(secondsInAuctionPeriod, 0, defaultExecutionWindow - 1);
        maxExecutionFee = bound(maxExecutionFee, 0, 1000000);
        minExecutionFee = bound(minExecutionFee, 0, maxExecutionFee);
        vm.prank(address(jobRegistry));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, minExecutionFee, maxExecutionFee));

        vm.warp(defaultStartTime + secondsInAuctionPeriod);
        vm.prank(address(jobRegistry));
        (uint256 executionFee,) = feeModule.onExecuteJob(0, from, defaultExecutionWindow, defaultStartTime, 0);

        uint256 correctExecutionFee = (
            ((maxExecutionFee - minExecutionFee) * secondsInAuctionPeriod) / (defaultExecutionWindow - 1)
        ) + minExecutionFee;

        assertEq(executionFee, correctExecutionFee, "execution fee mismatch");
    }

    function test_MinExecutionFeeGreaterThanMax() public {
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.MinExecutionFeeGreaterThanMax.selector));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, 100, 50));
    }

    function test_DeleteJob() public {
        vm.prank(address(jobRegistry));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, defaultMinExecutionFee, defaultMaxExecutionFee));
        vm.prank(address(jobRegistry));
        feeModule.onDeleteJob(0);
        (address executionFeeToken, uint256 minExecutionFee, uint256 maxExecutionFee) = feeModule.params(0);
        assertEq(executionFeeToken, address(0), "execution fee token not equal");
        assertEq(minExecutionFee, 0, "min execution fee not equal");
        assertEq(maxExecutionFee, 0, "max execution fee not equal");
    }

    function test_ExecuteNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon execution by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.NotJobRegistry.selector));
        feeModule.onExecuteJob(0, caller, defaultExecutionWindow, block.timestamp, 0);
    }

    function test_CreateJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon creation by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.NotJobRegistry.selector));
        feeModule.onCreateJob(0, "");
    }

    function test_DeleteJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon deletion by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.NotJobRegistry.selector));
        feeModule.onDeleteJob(0);
    }

    function test_UpdateDataNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon updating data by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.NotJobRegistry.selector));
        feeModule.onUpdateData(0, "");
    }

    function test_UpdateData(address executionFeeToken, uint256 minExecutionFee, uint256 maxExecutionFee) public {
        // Should update the job params correctly
        maxExecutionFee = bound(maxExecutionFee, 0, type(uint256).max);
        minExecutionFee = bound(minExecutionFee, 0, maxExecutionFee);
        uint256 jobIndex = 0;
        feeModule.setJobParams(jobIndex, address(0x01), 10, 100);
        vm.prank(address(jobRegistry));
        feeModule.onUpdateData(jobIndex, abi.encode(executionFeeToken, minExecutionFee, maxExecutionFee));
        (address _executionFeeToken, uint256 _minExecutionFee, uint256 _maxExecutionFee) = feeModule.params(jobIndex);
        assertEq(_executionFeeToken, executionFeeToken, "executionFeeToken mismatch");
        assertEq(_minExecutionFee, minExecutionFee, "minExecutionFee mismatch");
        assertEq(_maxExecutionFee, maxExecutionFee, "maxExecutionFee mismatch");
    }

    function test_UpdateDataMinExecutionFeeGreaterThanMax(
        address executionFeeToken,
        uint256 minExecutionFee,
        uint256 maxExecutionFee
    ) public {
        // Should revert with MinExecutionFeeGreaterThanMax when minExecutionFee > maxExecutionFee
        minExecutionFee = bound(minExecutionFee, 1, type(uint256).max);
        maxExecutionFee = bound(maxExecutionFee, 0, minExecutionFee - 1);
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(ILinearAuction.MinExecutionFeeGreaterThanMax.selector));
        feeModule.onUpdateData(0, abi.encode(defaultFeeToken, minExecutionFee, maxExecutionFee));
    }

    function test_EncodeData(address executionFeeToken, uint256 minExecutionFee, uint256 maxExecutionFee) public {
        // Should return the encoded data for the job
        uint256 jobIndex = 0;
        feeModule.setJobParams(jobIndex, executionFeeToken, minExecutionFee, maxExecutionFee);
        bytes memory encodedData = feeModule.getEncodedData(jobIndex);
        (address _executionFeeToken, uint256 _minExecutionFee, uint256 _maxExecutionFee) =
            abi.decode(encodedData, (address, uint256, uint256));
        assertEq(_executionFeeToken, executionFeeToken, "executionFeeToken mismatch");
        assertEq(_minExecutionFee, minExecutionFee, "minExecutionFee mismatch");
        assertEq(_maxExecutionFee, maxExecutionFee, "maxExecutionFee mismatch");
    }
}
