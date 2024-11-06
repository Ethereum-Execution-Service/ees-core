// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {RegularTimeInterval} from "../src/executionModules/RegularTimeInterval.sol";
import {LinearAuction} from "../src/feeModules/LinearAuction.sol";
import {PeggedLinearAuction} from "../src/feeModules/PeggedLinearAuction.sol";
import {Coordinator} from "../src/Coordinator.sol";
import {ICoordinator} from "../src/interfaces/ICoordinator.sol";

contract DeployAll is Script {
    address treasury;
    uint16 treasuryBasisPoints;
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner;

    ICoordinator.InitSpec initSpec;

    function setUp() public {
        // set to treasury
        treasury = 0x303cAE9641B868722194Bd9517eaC5ca2ad6e71a;
        treasuryBasisPoints = 2000;

        initSpec = ICoordinator.InitSpec({
            // Base sepolia USDC copy
            stakingToken: 0x7139F4601480d20d43Fa77780B67D295805aD31a,
            // 1000 USDC - 1000000000
            stakingAmount: 1000000000,
            // 30 seconds, should probably be something like 30 days in prod
            minimumStakingPeriod: 30 seconds,
            // 400 USDC - 400000000
            stakingBalanceThreshold: 400000000,
            // 200 USDC - 200000000
            inactiveSlashingAmount: 200000000,
            // 100 USDC - 100000000
            commitSlashingAmount: 100000000,
            roundDuration: 20,
            roundsPerEpoch: 5,
            roundBuffer: 15,
            commitPhaseDuration: 20,
            revealPhaseDuration: 20,
            slashingDuration: 15,
            // 0.05 USDC - 50000
            executorTax: 50000,
            // 0.05 USDC - 50000
            protocolTax: 50000
        });
    }

    function run()
        public
        returns (
            Coordinator coordinator,
            JobRegistry jobRegistry,
            RegularTimeInterval regularTimeInterval,
            LinearAuction linearAuction,
            PeggedLinearAuction peggedLinearAuction
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        coordinator = new Coordinator(initSpec, treasury);
        console2.log("Coordinator Deployed:", address(coordinator));

        jobRegistry = new JobRegistry(treasury, address(coordinator));
        console2.log("JobRegistry Deployed:", address(jobRegistry));

        coordinator.addJobRegistry(address(jobRegistry));

        regularTimeInterval = new RegularTimeInterval(jobRegistry);
        console2.log("RegularTimeInterval Deployed:", address(regularTimeInterval));

        linearAuction = new LinearAuction(jobRegistry);
        console2.log("LinearAuction Deployed:", address(linearAuction));

        peggedLinearAuction = new PeggedLinearAuction(jobRegistry, coordinator);
        console2.log("PeggedLinearAuction Deployed:", address(peggedLinearAuction));

        jobRegistry.addExecutionModule(regularTimeInterval);
        jobRegistry.addFeeModule(linearAuction);
        jobRegistry.addFeeModule(peggedLinearAuction);

        vm.stopBroadcast();
    }
}
