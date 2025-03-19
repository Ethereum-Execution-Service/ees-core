// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {SignatureGenerator} from "../utils/SignatureGenerator.sol";
import {DummyJobRegistry} from "../mocks/dummyContracts/DummyJobRegistry.sol";
import {DummyExecutionModule} from "../mocks/dummyContracts/DummyExecutionModule.sol";
import {DummyFeeModule} from "../mocks/dummyContracts/DummyFeeModule.sol";

contract CoordinatorBaseTest is Test, TokenProvider, SignatureGenerator, GasSnapshot {
    MockCoordinator coordinator;
    DummyJobRegistry jobRegistry;
    DummyExecutionModule dummyExecutionModule;
    DummyFeeModule dummyFeeModule;
    DummyFeeModule dummyFeeModule2;

    address defaultStakingToken;
    // same as executor
    address executor;
    uint256 executorPrivateKey;

    address secondExecutor;
    uint256 secondExecutorPrivateKey;

    address thirdExecutor;
    uint256 thirdExecutorPrivateKey;

    address nonStakedExecutor;
    uint256 nonStakedExecutorPrivateKey;

    uint256 stakingAmountPerModule = 500000000;
    uint256 stakingBalanceThresholdPerModule = 300000000;
    uint256 minimumRegistrationPeriod = 2;
    uint256 inactiveSlashingAmountPerModule = 200000000;
    uint256 commitSlashingAmountPerModule = 100000000;
    uint8 roundDuration = 15;
    uint8 roundsPerEpoch = 5;
    uint8 roundBuffer = 15;
    uint8 commitPhaseDuration = 15;
    uint8 revealPhaseDuration = 15;
    uint8 slashingDuration = 30;
    uint256 executionTax = 60000;
    uint256 zeroFeeExecutionTax = 20000;
    uint256 protocolPoolCutBps = 1000;

    uint256 defaultEpochEndTime = 1000;

    uint256 modulesToRegister = (1 << 0) | (1 << 1);

    address treasury = address(0x3);

    function setUp() public {
        initializeERC20Tokens();
        defaultStakingToken = address(token0);

        ICoordinator.InitSpec memory spec = ICoordinator.InitSpec({
            stakingToken: defaultStakingToken,
            stakingAmountPerModule: stakingAmountPerModule,
            minimumRegistrationPeriod: minimumRegistrationPeriod,
            stakingBalanceThresholdPerModule: stakingBalanceThresholdPerModule,
            inactiveSlashingAmountPerModule: inactiveSlashingAmountPerModule,
            commitSlashingAmountPerModule: commitSlashingAmountPerModule,
            roundDuration: roundDuration,
            roundsPerEpoch: roundsPerEpoch,
            roundBuffer: roundBuffer,
            commitPhaseDuration: commitPhaseDuration,
            revealPhaseDuration: revealPhaseDuration,
            slashingDuration: slashingDuration,
            executionTax: executionTax,
            zeroFeeExecutionTax: zeroFeeExecutionTax,
            protocolPoolCutBps: protocolPoolCutBps
        });
        coordinator = new MockCoordinator(spec, treasury);
        jobRegistry = new DummyJobRegistry();
        dummyExecutionModule = new DummyExecutionModule();
        dummyFeeModule = new DummyFeeModule(defaultStakingToken, 1_000_000);
        dummyFeeModule2 = new DummyFeeModule(defaultStakingToken, 500_000);
        vm.startPrank(treasury);
        coordinator.addJobRegistry(address(jobRegistry));
        coordinator.setEpochEndTime(defaultEpochEndTime);
        coordinator.addExecutionModule(dummyExecutionModule);
        coordinator.addFeeModule(dummyFeeModule);
        coordinator.addFeeModule(dummyFeeModule2);
        vm.stopPrank();

        executorPrivateKey = 0x12341234;
        executor = vm.addr(executorPrivateKey);

        secondExecutorPrivateKey = 0x43214321;
        secondExecutor = vm.addr(secondExecutorPrivateKey);

        thirdExecutorPrivateKey = 0x11111111;
        thirdExecutor = vm.addr(thirdExecutorPrivateKey);

        nonStakedExecutorPrivateKey = 0x22222222;
        nonStakedExecutor = vm.addr(nonStakedExecutorPrivateKey);

        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(coordinator));
        setERC20TestTokens(secondExecutor);
        setERC20TestTokenApprovals(vm, secondExecutor, address(coordinator));
        setERC20TestTokens(thirdExecutor);
        setERC20TestTokenApprovals(vm, thirdExecutor, address(coordinator));
        setERC20TestTokens(nonStakedExecutor);
        setERC20TestTokenApprovals(vm, nonStakedExecutor, address(coordinator));
    }
}
