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
    uint16 treasuryBasisPoints;
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner = 0xCE02d0981c1D4dCA9331178F322506C06E394bb0;

    ICoordinator.InitSpec initSpec;

    function setUp() public {
        // set to treasury
        treasuryBasisPoints = 2000;

        initSpec = ICoordinator.InitSpec({
            // Base sepolia USDC copy
            stakingToken: 0x7139F4601480d20d43Fa77780B67D295805aD31a,
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
            roundDuration: 20,
            roundsPerEpoch: 5,
            roundBuffer: 15,
            commitPhaseDuration: 15,
            revealPhaseDuration: 15,
            slashingDuration: 15,
            // 0.06 USDC - 60000
            executionTax: 60000,
            // 0.02 USDC - 20000
            zeroFeeExecutionTax: 20000,
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

        coordinator = new Coordinator(initSpec, owner);
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

        vm.stopBroadcast();
    }
}
