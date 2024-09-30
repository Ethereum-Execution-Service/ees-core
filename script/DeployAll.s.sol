// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {RegularTimeInterval} from "../src/executionModules/RegularTimeInterval.sol";
import {LinearAuction} from "../src/feeModules/LinearAuction.sol";
import {PeggedLinearAuction} from "../src/feeModules/PeggedLinearAuction.sol";
import {ExecutionManager} from "../src/ExecutionManager.sol";
import {IExecutionManager} from "../src/interfaces/IExecutionManager.sol";
// move to periphery
import {Querier} from "../src/Querier.sol";
import {ConfigProvider} from "../src/ConfigProvider.sol";

contract DeployAll is Script {
    address treasury;
    uint16 treasuryBasisPoints;
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner;

    IExecutionManager.InitSpec initSpec;

    function setUp() public {
        // set to treasury
        treasury = 0x303cAE9641B868722194Bd9517eaC5ca2ad6e71a;
        treasuryBasisPoints = 2000;

        initSpec = IExecutionManager.InitSpec({
            // Base sepolia USDC copy
            stakingToken: 0x7139F4601480d20d43Fa77780B67D295805aD31a,
            // 1000 USDC
            stakingAmount: 1000000000,
            // 400 USDC
            stakingBalanceThreshold: 400000000,
            // 200 USDC
            inactiveSlashingAmount: 200000000,
            // 100 USDC
            commitSlashingAmount: 100000000,
            roundDuration: 15,
            roundsPerEpoch: 5,
            roundBuffer: 15,
            commitPhaseDuration: 15,
            revealPhaseDuration: 15,
            slashingDuration: 15,
            // 0.05 USDC
            executorTax: 50000,
            // 0.05 USDC
            protocolTax: 50000
        });
    }

    function run()
        public
        returns (
            ExecutionManager executionManager,
            JobRegistry jobRegistry,
            RegularTimeInterval regularTimeInterval,
            LinearAuction linearAuction,
            PeggedLinearAuction peggedLinearAuction,
            Querier querier,
            ConfigProvider configProvider
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        executionManager = new ExecutionManager(initSpec, treasury);
        console2.log("ExecutionManager Deployed:", address(executionManager));

        jobRegistry = new JobRegistry(treasury, address(executionManager));
        console2.log("JobRegistry Deployed:", address(jobRegistry));

        executionManager.setJobRegistry(address(jobRegistry));

        regularTimeInterval = new RegularTimeInterval(jobRegistry);
        console2.log("RegularTimeInterval Deployed:", address(regularTimeInterval));

        linearAuction = new LinearAuction(jobRegistry);
        console2.log("LinearAuction Deployed:", address(linearAuction));

        peggedLinearAuction = new PeggedLinearAuction(jobRegistry);
        console2.log("PeggedLinearAuction Deployed:", address(peggedLinearAuction));

        jobRegistry.addExecutionModule(regularTimeInterval);
        jobRegistry.addFeeModule(linearAuction);
        jobRegistry.addFeeModule(peggedLinearAuction);

        querier = new Querier(jobRegistry);
        console2.log("Querier Deployed:", address(querier));

        configProvider = new ConfigProvider(jobRegistry, executionManager, querier);
        console2.log("ConfigProvider Deployed:", address(configProvider));

        vm.stopBroadcast();
    }
}
