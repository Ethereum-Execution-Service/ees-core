// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
import {MockPeggedLinearAuction} from "../mocks/MockPeggedLinearAuction.sol";
import {IPeggedLinearAuction} from "../../src/interfaces/feeModules/IPeggedLinearAuction.sol";
import {DummyPriceOracle} from "../mocks/dummyContracts/DummyPriceOracle.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

contract PeggedLinearAuctionTest is Test, GasSnapshot {
    MockPeggedLinearAuction feeModule;
    DummyPriceOracle dummyPriceOracle;

    address defaultFeeToken = address(0x3);
    uint256 defaultMinBps;
    uint256 defaultMaxBps;
    uint32 defaultExecutionWindow;
    uint256 defaultStartTime;

    address from;
    uint256 fromPrivateKey;

    address address0 = address(0x0);
    address address2 = address(0x2);
    JobRegistry jobRegistry;

    event ExecutionFee(uint256 executionFee, address executionFeeToken);

    function setUp() public {
        defaultMaxBps = 20000;
        defaultMinBps = 15000;
        defaultExecutionWindow = 1800;
        defaultStartTime = 1641070800;

        jobRegistry = new JobRegistry(address2, address2, 2);
        feeModule = new MockPeggedLinearAuction(jobRegistry);

        dummyPriceOracle = new DummyPriceOracle(100);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
    }

    function test_AuxDataCapture() public {
        bytes memory auxData = hex"123412343534589438942498238493284935849648964574957983";
        vm.prank(address(jobRegistry));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, dummyPriceOracle, defaultMinBps, defaultMaxBps, auxData));
        vm.prank(address(jobRegistry));
        vm.warp(defaultStartTime + 600);
        vm.fee(3157729);
        (uint256 executionFee, address executionFeeToken) =
            feeModule.onExecuteJob(0, from, defaultExecutionWindow, defaultStartTime, 0);
        emit ExecutionFee(executionFee, executionFeeToken);
        //assertEq(dummyPriceOracle.price(), 100, "price mismatch");
    }

    function test_MinFeeOverheadGreaterThanMax() public {
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.MinExecutionFeeGreaterThanMax.selector));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, dummyPriceOracle, 20000, 10000, ""));
    }

    function test_DeleteJob() public {
        vm.prank(address(jobRegistry));
        feeModule.onCreateJob(0, abi.encode(defaultFeeToken, dummyPriceOracle, defaultMinBps, defaultMaxBps, ""));
        vm.prank(address(jobRegistry));
        feeModule.onDeleteJob(0);
        (
            address executionFeeToken,
            IPriceOracle priceOracle,
            uint48 minOverheadBps,
            uint48 maxOverheadBps,
            bytes memory oracleData
        ) = feeModule.params(0);
        assertEq(executionFeeToken, address(0), "execution fee token not equal");
        assertEq(address(priceOracle), address(0), "price oracle not equal");
        assertEq(minOverheadBps, 0, "min overhead bps not equal");
        assertEq(maxOverheadBps, 0, "max overhead bps not equal");
        assertEq(oracleData.length, 0, "oracle data not equal");
    }

    function test_UpdateData(
        address executionFeeToken,
        IPriceOracle priceOracle,
        uint48 minOverheadBps,
        uint48 maxOverheadBps,
        bytes calldata oracleData
    ) public {
        // Should update the job params correctly
        maxOverheadBps = uint48(bound(maxOverheadBps, 0, type(uint48).max));
        minOverheadBps = uint48(bound(minOverheadBps, 0, maxOverheadBps));
        uint256 jobIndex = 0;
        feeModule.setJobParams(jobIndex, address(0x01), dummyPriceOracle, 10000, 20000, "");
        vm.prank(address(jobRegistry));
        feeModule.onUpdateData(
            jobIndex, abi.encode(executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData)
        );
        (
            address _executionFeeToken,
            IPriceOracle _priceOracle,
            uint48 _minOverheadBps,
            uint48 _maxOverheadBps,
            bytes memory _oracleData
        ) = feeModule.params(jobIndex);
        assertEq(_executionFeeToken, executionFeeToken, "executionFeeToken mismatch");
        assertEq(_minOverheadBps, minOverheadBps, "minOverheadBps mismatch");
        assertEq(_maxOverheadBps, maxOverheadBps, "maxOverheadBps mismatch");
        assertEq(address(_priceOracle), address(priceOracle), "priceOracle mismatch");
        assertEq(_oracleData, oracleData, "oracleData mismatch");
    }

    function test_UpdateDataMinExecutionFeeGreaterThanMax(
        address executionFeeToken,
        IPriceOracle priceOracle,
        uint48 minOverheadBps,
        uint48 maxOverheadBps,
        bytes calldata oracleData
    ) public {
        // Should revert with MinExecutionFeeGreaterThanMax when minExecutionFee > maxExecutionFee
        minOverheadBps = uint48(bound(minOverheadBps, 1, type(uint48).max));
        maxOverheadBps = uint48(bound(maxOverheadBps, 0, minOverheadBps - 1));
        uint256 jobIndex = 0;
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.MinExecutionFeeGreaterThanMax.selector));
        feeModule.onUpdateData(
            jobIndex, abi.encode(executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData)
        );
    }

    function test_EncodeData(
        address executionFeeToken,
        IPriceOracle priceOracle,
        uint48 minOverheadBps,
        uint48 maxOverheadBps,
        bytes calldata oracleData
    ) public {
        // Should return the encoded data for the job
        uint256 jobIndex = 0;
        feeModule.setJobParams(jobIndex, executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData);
        bytes memory encodedData = feeModule.getEncodedData(jobIndex);
        (
            address _executionFeeToken,
            IPriceOracle _priceOracle,
            uint48 _minOverheadBps,
            uint48 _maxOverheadBps,
            bytes memory _oracleData
        ) = abi.decode(encodedData, (address, IPriceOracle, uint48, uint48, bytes));
        assertEq(_executionFeeToken, executionFeeToken, "executionFeeToken mismatch");
        assertEq(_minOverheadBps, minOverheadBps, "minOverheadBps mismatch");
        assertEq(_maxOverheadBps, maxOverheadBps, "maxOverheadBps mismatch");
        assertEq(address(_priceOracle), address(priceOracle), "priceOracle mismatch");
        assertEq(_oracleData, oracleData, "oracleData mismatch");
    }

    function test_ExecuteNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon execution by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.NotJobRegistry.selector));
        feeModule.onExecuteJob(0, caller, defaultExecutionWindow, block.timestamp, 0);
    }

    function test_CreateJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon creation by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.NotJobRegistry.selector));
        feeModule.onCreateJob(0, "");
    }

    function test_DeleteJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon deletion by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.NotJobRegistry.selector));
        feeModule.onDeleteJob(0);
    }

    function test_UpdateDataNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon updating data by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPeggedLinearAuction.NotJobRegistry.selector));
        feeModule.onUpdateData(0, "");
    }
}
