// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {SafeERC20, IERC20, IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenProvider} from "./utils/TokenProvider.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {SignatureExpired, InvalidNonce} from "../src/PermitErrors.sol";
import {IJobRegistry} from "../src/interfaces/IJobRegistry.sol";
import {IApplication} from "../src/interfaces/IApplication.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {DummyApplication} from "./mocks/dummyContracts/DummyApplication.sol";
import {DummyExecutionModule} from "./mocks/dummyContracts/DummyExecutionModule.sol";
import {DummyFeeModule} from "./mocks/dummyContracts/DummyFeeModule.sol";
import {JobSpecificationSignature} from "./utils/JobSpecificationSignature.sol";
import {FeeModuleInputSignature} from "./utils/FeeModuleInputSignature.sol";
import {StdUtils} from "lib/forge-std/src/StdUtils.sol";

contract JobRegistryTest is Test, TokenProvider, JobSpecificationSignature, FeeModuleInputSignature, GasSnapshot {
    JobRegistry jobRegistry;
    DummyApplication dummyApplication;
    DummyExecutionModule dummyExecutionModule;
    DummyFeeModule dummyFeeModule;

    address defaultFeeToken;

    event Signature(bytes sig);
    event Sponsor(address sponsor);

    address from;
    uint256 fromPrivateKey;
    address sponsor;
    uint256 sponsorPrivateKey;

    uint8 defaultProtocolFeeRatio;
    uint256 defaultMaxExecutionFee;
    uint32 defaultExecutionWindow;

    address address0 = address(0x0);
    address address2 = address(0x2);

    address treasury = address(0x3);

    address executor = address(0x4);

    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        defaultProtocolFeeRatio = 2;
        defaultMaxExecutionFee = 100;
        defaultExecutionWindow = 1800;
        vm.prank(address0);
        jobRegistry = new JobRegistry(address2, treasury, defaultProtocolFeeRatio);

        initializeERC20Tokens();
        defaultFeeToken = address(token0);

        dummyExecutionModule = new DummyExecutionModule(jobRegistry);
        dummyFeeModule = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);

        vm.prank(address2);
        jobRegistry.addExecutionModule(dummyExecutionModule);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);

        dummyApplication = new DummyApplication(jobRegistry);

        sponsorPrivateKey = 0x43214321;
        sponsor = vm.addr(sponsorPrivateKey);

        setERC20TestTokens(from);
        setERC20TestTokenApprovals(vm, from, address(jobRegistry));
        setERC20TestTokens(sponsor);
        setERC20TestTokenApprovals(vm, sponsor, address(jobRegistry));
        setERC20TestTokens(executor);
        setERC20TestTokenApprovals(vm, executor, address(jobRegistry));
    }

    function test_CreateJobWithoutSponsor() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_CreateJobWithSponsor() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);
    }

    function test_CreateJobWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // Should revert with SignatureExpired if deadline is in the past
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: deadline,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        vm.warp(createTime);
        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);
    }

    function test_CreateJobWithSponsorReusingNonce() public {
        // Should revert with InvalidNonce if nonce is already used
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(InvalidNonce.selector));
        jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);
    }

    function testFail_CreationWithUnsupportedExecutionModule(bytes1 module) public {
        vm.assume(module != 0x00);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: module,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
    }

    function testFail_CreationWithUnsupportedFeeModule(bytes1 module) public {
        vm.assume(module != 0x00);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: module,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
    }

    function test_DeleteExpiredJob(address caller) public {
        // Anyone should be able to delete a job that is expired (even if application reverts)
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        dummyExecutionModule.expireJob();
        dummyApplication.setRevertOnDelete(true);

        vm.prank(caller);
        jobRegistry.deleteJob(index);
    }

    function test_DeleteActiveJobAsOwner() public {
        // Should be able to delete an active job as the owner
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);
        (address owner,,,,,,,) = jobRegistry.jobs(index);
        assertEq(owner, address(0));
    }

    function test_DeleteJobReachedMaxExecutions(address caller) public {
        // Anyone should be able to delete a job that has reached max executions
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 1,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        vm.prank(caller);
        jobRegistry.deleteJob(index);
    }

    function test_DeleteActiveJobNonOwner(address caller) public {
        // Should revert when trying to delete an active job as a non-owner
        vm.assume(caller != from);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.deleteJob(index);
    }

    function test_RevokeSponsorshipSponsor() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);

        vm.prank(sponsor);
        jobRegistry.revokeSponsorship(index);
        (, address sponsorSet,,,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorshipOwner() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);

        vm.prank(from);
        jobRegistry.revokeSponsorship(index);
        (, address sponsorSet,,,,,,) = jobRegistry.jobs(index);

        assertEq(sponsorSet, from);
    }

    function test_RevokeSponsorShipNotOwnerOrSponsor(address caller) public {
        vm.assume(caller != from && caller != sponsor);

        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.revokeSponsorship(index);
    }

    function test_ExecuteDeletedJob() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);

        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobIsDeleted.selector));
        jobRegistry.execute(index, from, "");
    }

    function test_BalancesExecuteNoSponsor(uint256 _executionFee) public {
        uint256 startBalanceFrom = token0.balanceOf(from);
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceTreasury = token0.balanceOf(treasury);
        _executionFee = bound(_executionFee, 0, startBalanceFrom);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        dummyFeeModule.setExecutionFee(_executionFee);
        vm.prank(executor);
        (uint256 executionFee,) = jobRegistry.execute(index, executor, "");

        assertEq(_executionFee, executionFee, "execution fee mismatch");
        assertEq(token0.balanceOf(from), startBalanceFrom - executionFee, "from balance");
        assertEq(
            token0.balanceOf(executor),
            startBalanceExecutor + (executionFee - (executionFee / defaultProtocolFeeRatio)),
            "executor balance"
        );
        assertEq(
            token0.balanceOf(treasury),
            startBalanceTreasury + (executionFee / defaultProtocolFeeRatio),
            "treasury balance"
        );
    }

    function test_BalancesExecuteWithSponsor(uint256 _executionFee) public {
        uint256 startBalanceFrom = token0.balanceOf(from);
        uint256 startBalanceExecutor = token0.balanceOf(executor);
        uint256 startBalanceTreasury = token0.balanceOf(treasury);
        uint256 startBalanceSponsor = token0.balanceOf(sponsor);
        _executionFee = bound(_executionFee, 0, startBalanceFrom);

        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        bytes memory sponsorSig =
            getJobSpecificationSignature(jobSpecification, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, sponsorSig, true, UINT256_MAX);

        dummyFeeModule.setExecutionFee(_executionFee);
        vm.prank(executor);
        (uint256 executionFee,) = jobRegistry.execute(index, executor, "");

        assertEq(_executionFee, executionFee, "execution fee mismatch");
        assertEq(token0.balanceOf(from), startBalanceFrom, "from balance");
        assertEq(token0.balanceOf(sponsor), startBalanceSponsor - executionFee, "sponsor balance");
        assertEq(
            token0.balanceOf(executor),
            startBalanceExecutor + (executionFee - (executionFee / defaultProtocolFeeRatio)),
            "executor balance"
        );
        assertEq(
            token0.balanceOf(treasury),
            startBalanceTreasury + (executionFee / defaultProtocolFeeRatio),
            "treasury balance"
        );
    }

    function test_ReuseJobIndex() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        vm.prank(from);
        jobRegistry.deleteJob(index);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            nonce: 1,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(jobSpecification2, sponsor, "", false, index);

        (address owner,,,,,,,) = jobRegistry.jobs(index);

        assertEq(index, index2, "index mismatch");
        assertEq(owner, address2, "owner mismatch");
        assertEq(jobRegistry.getJobsArrayLength(), 1, "jobs array length mismatch");
    }

    function test_ReuseJobIndexAlreadyTaken() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            nonce: 1,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(address2);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobAlreadyExistsAtIndex.selector));
        jobRegistry.createJob(jobSpecification2, sponsor, "", false, index);
    }

    function test_CreateJobEndOfArray() public {
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        IJobRegistry.JobSpecification memory jobSpecification2 = IJobRegistry.JobSpecification({
            nonce: 1,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(address2);
        uint256 index2 = jobRegistry.createJob(jobSpecification2, sponsor, "", false, UINT256_MAX);

        (address owner,,,,,,,) = jobRegistry.jobs(index);
        (address owner2,,,,,,,) = jobRegistry.jobs(index2);

        assertEq(index, 0);
        assertEq(index2, 1);
        assertEq(owner, from);
        assertEq(owner2, address2);
    }

    function test_UpdateFeeModuleWithSponsor() public {
        // Should be able to update fee module with sponsorship
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x00,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig, true);
        (, address sponsorSet,,,,, bytes1 feeModuleSet,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x00), "fee module mismatch");
    }

    function test_UpdateFeeModuleWithSponsorExpiredSignature(uint256 createTime, uint256 deadline) public {
        // Should revert with ExpiredSignature when updating fee module with an expired signature
        createTime = bound(createTime, 1, block.timestamp);
        deadline = bound(deadline, 0, createTime - 1);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: deadline,
            index: index,
            feeModule: 0x00,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        vm.warp(createTime);
        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig, true);
    }

    function test_UpdateFeeModuleDataNoSponsor() public {
        // Should be able to update fee module without sponsorship
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });

        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);

        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);

        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x00,
            feeModuleInput: ""
        });

        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, "", false);
        (, address sponsorSet,,,,, bytes1 feeModuleSet,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, from, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x00), "fee module mismatch");
    }

    function test_UpdateFeeModuleInExecutionMode() public {
        // Should revert with JobInExecutionMode when updating fee module of a job that is in execution mode
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x00,
            feeModuleInput: ""
        });
        dummyExecutionModule.setIsInExecutionMode(true);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.JobInExecutionMode.selector));
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, "", false);
    }

    function test_UpdateFeeModuleNotOwner(address caller) public {
        // Should revert with Unauthorized when updating fee module of a job from a caller that is not the owner of the job
        vm.assume(caller != from);
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x00,
            feeModuleInput: ""
        });
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.Unauthorized.selector));
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, "", false);
    }

    function test_MigrateFeeModuleWithSponsor() public {
        // Should be able to migrate fee module with sponsorship
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        vm.prank(from);
        uint256 index = jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        DummyFeeModule dummyFeeModule2 = new DummyFeeModule(jobRegistry, defaultFeeToken, 1_000_000);
        vm.prank(address2);
        jobRegistry.addFeeModule(dummyFeeModule2);
        IJobRegistry.FeeModuleInput memory feeModuleInput = IJobRegistry.FeeModuleInput({
            nonce: 1,
            deadline: UINT256_MAX,
            index: index,
            feeModule: 0x01,
            feeModuleInput: ""
        });
        bytes memory sponsorSig =
            getFeeModuleInputSignature(feeModuleInput, sponsorPrivateKey, jobRegistry.DOMAIN_SEPARATOR());
        vm.prank(from);
        jobRegistry.updateFeeModule(feeModuleInput, sponsor, sponsorSig, true);
        (, address sponsorSet,,,,, bytes1 feeModuleSet,) = jobRegistry.jobs(index);
        assertEq(sponsorSet, sponsor, "sponsor mismatch");
        assertEq(uint8(feeModuleSet), uint8(0x01), "fee module mismatch");
    }

    function test_CreateJobInitialExecution() public {
        // Should execute once when execution module returns true for initial execution
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        (,, uint48 executionCounter,,,,,) = jobRegistry.jobs(0);
        assertEq(executionCounter, 1, "execution counter mismatch");
    }

    function test_NoMaxExecutionLimit() public {
        // Should be able to execute twice when maxExecutions is set to 0
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 0,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        jobRegistry.execute(0, from, "");
    }

    function test_MaxExecutionLimitOfOne() public {
        // Should revert when trying to execute more than once when maxExecutions set to 1
        IJobRegistry.JobSpecification memory jobSpecification = IJobRegistry.JobSpecification({
            nonce: 0,
            deadline: UINT256_MAX,
            application: dummyApplication,
            executionWindow: defaultExecutionWindow,
            maxExecutions: 1,
            executionModule: 0x00,
            feeModule: 0x00,
            executionModuleInput: "",
            feeModuleInput: "",
            applicationInput: ""
        });
        dummyExecutionModule.setInitialExecution(true);
        vm.prank(from);
        jobRegistry.createJob(jobSpecification, sponsor, "", false, UINT256_MAX);
        vm.expectRevert(abi.encodeWithSelector(IJobRegistry.MaxExecutionsExceeded.selector));
        jobRegistry.execute(0, from, "");
    }

    function test_UpdateProtocolFeeRatio(uint8 protocolFeeRatio) public {
        // Should be able to update protocol fee ratio
        vm.prank(address2);
        jobRegistry.updateProtocolFeeRatio(protocolFeeRatio);
        assertEq(jobRegistry.protocolFeeRatio(), protocolFeeRatio, "protocol fee ratio mismatch");
    }

    function testFail_UpdateProtocolFeeRatioNotOwner(address caller) public {
        // Should revert when updating protocol fee ratio from a caller that is not the owner of JobRegistry
        vm.assume(caller != address2);
        vm.prank(caller);
        jobRegistry.updateProtocolFeeRatio(1);
    }

    function test_WithdrawProtocolFee(uint256 tokenAmount) public {
        // Should be able to withdraw protocol fee
        uint256 startBalanceTreasury = token0.balanceOf(treasury);
        deal(address(token0), address(jobRegistry), tokenAmount);
        vm.prank(address2);
        jobRegistry.withdrawProtocolFee(address(token0), treasury);
        assertEq(token0.balanceOf(treasury), startBalanceTreasury + tokenAmount, "treasury balance mismatch");
    }

    function testFail_WithdrawProtocolFeeNotOwner(address caller) public {
        // Should revert when trying to withdraw protocol fee as non-owner
        vm.assume(caller != address2);
        uint256 startBalanceTreasury = token0.balanceOf(treasury);
        deal(address(token0), address(jobRegistry), 100);
        vm.prank(caller);
        jobRegistry.withdrawProtocolFee(address(token0), treasury);
    }
}
