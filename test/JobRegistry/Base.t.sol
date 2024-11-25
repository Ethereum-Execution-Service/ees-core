// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/src/GasSnapshot.sol";
import {JobSpecificationSignature} from "../utils/JobSpecificationSignature.sol";
import {FeeModuleInputSignature} from "../utils/FeeModuleInputSignature.sol";
import {MockJobRegistry} from "../mocks/MockJobRegistry.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {DummyApplication} from "../mocks/dummyContracts/DummyApplication.sol";
import {DummyExecutionModule} from "../mocks/dummyContracts/DummyExecutionModule.sol";
import {DummyFeeModule} from "../mocks/dummyContracts/DummyFeeModule.sol";
import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";
import {MockCoordinatorProvider} from "../utils/MockCoordinatorProvider.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

contract JobRegistryBaseTest is Test, TokenProvider, JobSpecificationSignature, FeeModuleInputSignature, GasSnapshot {
    MockJobRegistry jobRegistry;
    MockCoordinator coordinator;
    DummyApplication dummyApplication;
    DummyExecutionModule dummyExecutionModule;
    DummyFeeModule dummyFeeModule;

    address defaultFeeToken;

    address from;
    uint256 fromPrivateKey;
    address sponsor;
    uint256 sponsorPrivateKey;
    address sponsor2;
    uint256 sponsor2PrivateKey;

    uint8 defaultProtocolFeeRatio;
    uint256 defaultMaxExecutionFee;
    uint24 defaultExecutionWindow;
    uint24 defaultZeroFeeWindow;

    address address0 = address(0x0);
    address address2 = address(0x2);
    address treasury = address(0x3);
    address executor = address(0x4);

    IJobRegistry.JobSpecification genericJobSpecification;

    function setUp() public virtual {
        defaultProtocolFeeRatio = 2;
        defaultMaxExecutionFee = 100;
        defaultExecutionWindow = 1800;
        defaultZeroFeeWindow = 0;
        initializeERC20Tokens();
        defaultFeeToken = address(token0);

        MockCoordinatorProvider coordinatorProvider = new MockCoordinatorProvider(treasury);
        coordinator = MockCoordinator(coordinatorProvider.getMockCoordinator());

        dummyExecutionModule = new DummyExecutionModule();
        dummyFeeModule = new DummyFeeModule(defaultFeeToken, 1_000_000);

        vm.startPrank(treasury);
        coordinator.addExecutionModule(dummyExecutionModule);
        coordinator.addFeeModule(dummyFeeModule);
        vm.stopPrank();

        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator();
        vm.prank(address0);
        jobRegistry = new MockJobRegistry(coordinator, publicERC6492Validator);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);

        dummyApplication = new DummyApplication(jobRegistry);

        sponsorPrivateKey = 0x43214321;
        sponsor = vm.addr(sponsorPrivateKey);

        sponsor2PrivateKey = 0x56785678;
        sponsor2 = vm.addr(sponsor2PrivateKey);

        genericJobSpecification = IJobRegistry.JobSpecification({
            owner: from,
            nonce: 0,
            deadline: UINT256_MAX,
            reusableNonce: false,
            sponsorFallbackToOwner: false,
            sponsorCanUpdateFeeModule: false,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            zeroFeeWindow: defaultZeroFeeWindow,
            ignoreAppRevert: false,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x01,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        setERC20TestTokens(from);
        setERC20TestTokenApprovals(vm, from, address(jobRegistry));
        setERC20TestTokens(sponsor);
        setERC20TestTokenApprovals(vm, sponsor, address(jobRegistry));
        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(jobRegistry));
    }
}