// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {RegularTimeInterval} from "../src/executionModules/RegularTimeInterval.sol";
import {LinearAuction} from "../src/feeModules/LinearAuction.sol";
import {PeggedLinearAuction} from "../src/feeModules/PeggedLinearAuction.sol";

contract DeployAll is Script {
    address treasury;
    uint16 treasuryBasisPoints;
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner;

    function setUp() public {
        // set to treasury
        treasury = 0x303cAE9641B868722194Bd9517eaC5ca2ad6e71a;
        treasuryBasisPoints = 2000;
        protocolFeeRatio = 2;
    }

    function run()
        public
        returns (
            JobRegistry jobRegistry,
            RegularTimeInterval regularTimeInterval,
            LinearAuction linearAuction,
            PeggedLinearAuction peggedLinearAuction
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        jobRegistry = new JobRegistry(treasury, protocolFeeRatio);
        console2.log("JobRegistry Deployed:", address(jobRegistry));

        regularTimeInterval = new RegularTimeInterval(jobRegistry);
        console2.log("RegularTimeInterval Deployed:", address(regularTimeInterval));

        linearAuction = new LinearAuction(jobRegistry);
        console2.log("LinearAuction Deployed:", address(linearAuction));

        peggedLinearAuction = new PeggedLinearAuction(jobRegistry);
        console2.log("PeggedLinearAuction Deployed:", address(peggedLinearAuction));

        jobRegistry.addExecutionModule(regularTimeInterval);
        jobRegistry.addFeeModule(linearAuction);
        jobRegistry.addFeeModule(peggedLinearAuction);

        vm.stopBroadcast();
    }
}
