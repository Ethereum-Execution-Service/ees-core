// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {RegularTimeInterval} from "../src/executionModules/RegularTimeInterval.sol";
import {LinearAuction} from "../src/feeModules/LinearAuction.sol";
import {PeggedLinearAuction} from "../src/feeModules/PeggedLinearAuction.sol";
import {Coordinator} from "../src/Coordinator.sol";
import {ICoordinator} from "../src/interfaces/ICoordinator.sol";
import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";

contract DeployAll is Script {
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner = 0xfd8eFb4061Aa7849fFBFE4DaDE414151dd8fA332;

    address deployer = 0x314ceF6386726935Fbe7de297c01104f4B3654a1;

    ICoordinator.InitSpec initSpec;

    function setUp() public {
        initSpec = ICoordinator.InitSpec({
            // Base USDC
            stakingToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            // 100 USDC - 100000000
            stakingAmountPerModule: 100000000,
            // 30 days
            minimumRegistrationPeriod: 30 days,
            // 30 USDC - 30000000
            stakingBalanceThresholdPerModule: 30000000,
            // 20 USDC - 20000000
            inactiveSlashingAmountPerModule: 20000000,
            // 10 USDC - 10000000
            commitSlashingAmountPerModule: 10000000,
            roundDuration: 30,
            roundsPerEpoch: 5,
            roundBuffer: 30,
            commitPhaseDuration: 30,
            revealPhaseDuration: 30,
            slashingDuration: 30,
            // 0.03 USDC - 30000
            executionTax: 30000,
            // 0.01 USDC - 10000
            zeroFeeExecutionTax: 10000,
            // 10% in basis points
            protocolPoolCutBps: 1000
        });
    }

    function run()
        public
        returns (
            Coordinator coordinator,
            PublicERC6492Validator publicERC6492Validator,
            JobRegistry jobRegistry,
            RegularTimeInterval regularTimeInterval,
            LinearAuction linearAuction,
            PeggedLinearAuction peggedLinearAuction
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        coordinator = new Coordinator(initSpec, deployer);
        console2.log("Coordinator Deployed:", address(coordinator));

        publicERC6492Validator = new PublicERC6492Validator();
        console2.log("PublicERC6492Validator Deployed:", address(publicERC6492Validator));

        jobRegistry = new JobRegistry(coordinator, publicERC6492Validator);
        console2.log("JobRegistry Deployed:", address(jobRegistry));

        coordinator.addJobRegistry(address(jobRegistry));

        regularTimeInterval = new RegularTimeInterval(coordinator);
        console2.log("RegularTimeInterval Deployed:", address(regularTimeInterval));

        linearAuction = new LinearAuction(coordinator);
        console2.log("LinearAuction Deployed:", address(linearAuction));

        /*
        peggedLinearAuction = new PeggedLinearAuction(coordinator);
        console2.log("PeggedLinearAuction Deployed:", address(peggedLinearAuction));
        */

        coordinator.addExecutionModule(regularTimeInterval);
        coordinator.addFeeModule(linearAuction);
        //coordinator.addFeeModule(peggedLinearAuction);

        coordinator.transferOwnership(owner);

        vm.stopBroadcast();
    }
}
