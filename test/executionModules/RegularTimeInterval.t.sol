// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {SafeERC20, IERC20, IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";
import {JobRegistry} from "../../src/JobRegistry.sol";
import {JobSpecificationSignature} from "../utils/JobSpecificationSignature.sol";
import {IRegularTimeInterval} from "../../src/interfaces/executionModules/IRegularTimeInterval.sol";
import {MockRegularTimeInterval} from "../mocks/MockRegularTimeInterval.sol";

contract RegularTimeIntervalTest is Test, TokenProvider, JobSpecificationSignature, GasSnapshot {
    JobRegistry jobRegistry;
    MockRegularTimeInterval executionModule;

    uint256 defaultStartTime;
    uint32 defaultExecutionWindow;

    address from;
    uint256 fromPrivateKey;

    address address0 = address(0x0);
    address address2 = address(0x2);

    function setUp() public {
        defaultExecutionWindow = 1800;
        defaultStartTime = 1641070800;
        vm.prank(address0);
        jobRegistry = new JobRegistry(address2, address2, 2);
        executionModule = new MockRegularTimeInterval(jobRegistry);
        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
    }

    function test_ExecuteWithinCooldown(uint32 cooldown, uint256 secondsInCooldown) public {
        cooldown = uint32(bound(cooldown, defaultExecutionWindow, defaultStartTime));
        secondsInCooldown = bound(secondsInCooldown, 0, cooldown - 1);
        vm.warp(defaultStartTime);
        vm.prank(address(jobRegistry));
        executionModule.onCreateJob(0, abi.encode(cooldown, defaultStartTime), defaultExecutionWindow);
        vm.warp(defaultStartTime + secondsInCooldown);
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.NotEnoughTimePast.selector));
        executionModule.onExecuteJob(0, defaultExecutionWindow, "");
    }

    function test_ImmediateExecution(uint40 initialExecutionTime, uint40 creationTime) public {
        // Should set lastExecution to the current time upon creation of job when initialExecutionTime is before or equal to block.timestamp
        initialExecutionTime = uint32(bound(initialExecutionTime, 0, creationTime));
        vm.warp(creationTime);
        vm.prank(address(jobRegistry));
        bool initialExecution =
            executionModule.onCreateJob(0, abi.encode(1800, initialExecutionTime), defaultExecutionWindow);
        (uint40 lastExecution,) = executionModule.params(0);
        assertEq(lastExecution, creationTime, "lastExecution mismatch");
        assertTrue(initialExecution, "initialExecution mismatch");
    }

    function test_ExecutingWithinExecutionWindow(uint40 startWindowTime, uint40 executionTime) public {
        // Should be able to execute job after initial execution time and thorughout the execution window
        startWindowTime = uint40(bound(startWindowTime, 1, type(uint40).max - defaultExecutionWindow - 1800));
        executionTime = uint40(bound(executionTime, startWindowTime, startWindowTime + defaultExecutionWindow - 1));
        vm.warp(startWindowTime);
        vm.prank(address(jobRegistry));
        executionModule.onCreateJob(0, abi.encode(1800, startWindowTime), defaultExecutionWindow);

        vm.warp(executionTime + 1800);
        vm.prank(address(jobRegistry));
        executionModule.onExecuteJob(0, defaultExecutionWindow, "");
    }

    function test_ExecutionAfterExpiry(uint40 startWindowTime, uint40 executionTime) public {
        // Should revert with JobExpired upon execution of an expired job
        startWindowTime = uint40(bound(startWindowTime, 1, type(uint40).max - defaultExecutionWindow - 1800));
        executionTime = uint40(bound(executionTime, startWindowTime + defaultExecutionWindow, type(uint40).max - 1800));
        vm.warp(startWindowTime);
        vm.prank(address(jobRegistry));
        executionModule.onCreateJob(0, abi.encode(1800, startWindowTime), defaultExecutionWindow);

        vm.warp(executionTime + 1800);
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.JobExpired.selector));
        executionModule.onExecuteJob(0, defaultExecutionWindow, "");
    }

    function test_ExecuteNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon execution by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.NotJobRegistry.selector));
        executionModule.onExecuteJob(0, defaultExecutionWindow, "");
    }

    function test_CreateJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon creation by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.NotJobRegistry.selector));
        executionModule.onCreateJob(0, "", defaultExecutionWindow);
    }

    function test_DeleteJobNotJobRegistry(address caller) public {
        // Should revert with NotJobRegistry upon deletion by a non-JobRegistry contract
        vm.assume(caller != address(jobRegistry));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.NotJobRegistry.selector));
        executionModule.onDeleteJob(0);
    }

    function test_DeleteJob() public {
        // JobRegistry should be able to call onDeleteJob and delete the job from params
        vm.prank(address(jobRegistry));
        executionModule.onCreateJob(0, abi.encode(1800, block.timestamp), defaultExecutionWindow);

        vm.prank(address(jobRegistry));
        executionModule.onDeleteJob(0);
        (uint40 lastExecution, uint32 cooldown) = executionModule.params(0);
        assertEq(lastExecution, 0, "lastExecution mismatch");
        assertEq(cooldown, 0, "cooldown mismatch");
    }

    function test_CreateJobCooldownLessThanExecutionWindow() public {
        // Should revert with CooldownLessThanExecutionWindow upon creation with cooldown less than execution window
        vm.prank(address(jobRegistry));
        vm.expectRevert(abi.encodeWithSelector(IRegularTimeInterval.CooldownLessThanExecutionWindow.selector));
        executionModule.onCreateJob(0, abi.encode(1800, block.timestamp), 1801);
    }

    function test_CreateJobInitialExecution(uint40 creationTime, uint40 initialExecutionTime) public {
        // Should set lastExecution to block.timestamp upon creation of job when initialExecutionTime is before or equal to block.timestamp
        creationTime = uint40(bound(creationTime, 0, type(uint40).max));
        initialExecutionTime = uint40(bound(initialExecutionTime, 0, creationTime));
        vm.warp(creationTime);
        vm.prank(address(jobRegistry));
        bool initialExecution =
            executionModule.onCreateJob(0, abi.encode(1800, initialExecutionTime), defaultExecutionWindow);
        (uint40 lastExecution,) = executionModule.params(0);
        assertEq(lastExecution, creationTime, "lastExecution mismatch");
        assertTrue(initialExecution, "initialExecution mismatch");
    }

    function test_CreateJobNoInitialExecution(uint40 creationTime, uint40 initialExecutionTime) public {
        // Should set lastExecution to initialExecutionTime - cooldown when initialExecutionTime is after block.timestamp
        initialExecutionTime = uint40(bound(initialExecutionTime, 1800, type(uint40).max));
        creationTime = uint40(bound(creationTime, 0, initialExecutionTime - 1));
        vm.warp(creationTime);
        vm.prank(address(jobRegistry));
        bool initialExecution =
            executionModule.onCreateJob(0, abi.encode(1800, initialExecutionTime), defaultExecutionWindow);
        (uint40 lastExecution,) = executionModule.params(0);
        assertEq(lastExecution, initialExecutionTime - 1800, "lastExecution mismatch");
        assertFalse(initialExecution, "initialExecution mismatch");
    }

    function test_JobIsExpired(uint32 cooldown, uint40 lastExecution, uint32 executionWindow, uint256 time) public {
        // Should return true when the job is expired
        time = bound(time, uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow), type(uint256).max);
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        vm.warp(time);
        bool isExpired = executionModule.jobIsExpired(jobIndex, executionWindow);
        assertTrue(isExpired, "Job should be expired");
    }

    function test_JobIsNotExpired(uint32 cooldown, uint40 lastExecution, uint32 executionWindow, uint256 time) public {
        // Should return false when the job is not expired
        vm.assume(uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow) > 0);
        time = bound(time, 0, uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow) - 1);
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        vm.warp(time);
        bool isExpired = executionModule.jobIsExpired(jobIndex, executionWindow);
        assertFalse(isExpired, "Job should not be expired");
    }

    function test_JobIsInExecutionMode(uint32 cooldown, uint40 lastExecution, uint32 executionWindow, uint256 time)
        public
    {
        // Should return true when the job is in execution mode
        executionWindow = uint32(bound(executionWindow, 1, type(uint32).max));
        vm.assume(uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow) > 0);
        time = bound(
            time,
            uint256(lastExecution) + uint256(cooldown),
            uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow) - 1
        );
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        vm.warp(time);
        bool isInExecutionMode = executionModule.jobIsInExecutionMode(jobIndex, executionWindow);
        assertTrue(isInExecutionMode, "Job should be in execution mode");
    }

    function test_JobIsBeforeExecutionMode(uint32 cooldown, uint40 lastExecution, uint32 executionWindow, uint256 time)
        public
    {
        // Should return false when the job is before execution mode
        vm.assume(uint256(lastExecution) + uint256(cooldown) > 0);
        time = bound(time, 0, uint256(lastExecution) + uint256(cooldown) - 1);
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        vm.warp(time);
        bool isInExecutionMode = executionModule.jobIsInExecutionMode(jobIndex, executionWindow);
        assertFalse(isInExecutionMode, "Job should not be in execution mode");
    }

    function test_JobIsAfterExecutionMode(uint32 cooldown, uint40 lastExecution, uint32 executionWindow, uint256 time)
        public
    {
        // Should return false when the job is after execution mode
        executionWindow = uint32(bound(executionWindow, 1, type(uint32).max));
        time = bound(time, uint256(lastExecution) + uint256(cooldown) + uint256(executionWindow), type(uint256).max);
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        vm.warp(time);
        bool isInExecutionMode = executionModule.jobIsInExecutionMode(jobIndex, executionWindow);
        assertFalse(isInExecutionMode, "Job should not be in execution mode");
    }

    function test_EncodeData(uint40 lastExecution, uint32 cooldown) public {
        // Should return the encoded data for the job
        uint256 jobIndex = 0;
        executionModule.setJobParams(jobIndex, lastExecution, cooldown);
        bytes memory encodedData = executionModule.getEncodedData(jobIndex);
        (uint40 _lastExecution, uint32 _cooldown) = abi.decode(encodedData, (uint40, uint32));
        assertEq(_lastExecution, lastExecution, "lastExecution mismatch");
        assertEq(_cooldown, cooldown, "cooldown mismatch");
    }
}
