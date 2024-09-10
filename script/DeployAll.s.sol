// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {AutoPay} from "../src/applications/AutoPay.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {RegularTimeInterval} from "../src/executionModules/RegularTimeInterval.sol";
import {LinearAuction} from "../src/feeModules/LinearAuction.sol";
import {PeggedLinearAuction} from "../src/feeModules/PeggedLinearAuction.sol";
import {Querier} from "../src/Querier.sol";
import {AutoPayQuerier} from "../src/AutoPayQuerier.sol";
import {PayNFT} from "../src/extras/PayNFT.sol";

contract DeployAll is Script {
    address treasury;
    uint16 treasuryBasisPoints;
    uint8 protocolFeeRatio;
    // owner is deployer
    address owner;

    function setUp() public {
        // set to treasury
        treasury = 0x84cC05F95B87fd9ba181C43562d89Ea5e605F6D0;
        treasuryBasisPoints = 2000;
        owner = 0x303cAE9641B868722194Bd9517eaC5ca2ad6e71a;
        protocolFeeRatio = 2;
    }

    function run()
        public
        returns (
            JobRegistry jobRegistry,
            RegularTimeInterval regularTimeInterval,
            LinearAuction linearAuction,
            PeggedLinearAuction peggedLinearAuction,
            AutoPay autoPay,
            BatchExecutor batchExecutor,
            Querier querier,
            AutoPayQuerier autoPayQuerier,
            PayNFT payNFT
        )
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        jobRegistry = new JobRegistry(owner, treasury, protocolFeeRatio);
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

        autoPay = new AutoPay(jobRegistry, treasury, treasuryBasisPoints, owner);
        console2.log("AutoPay Deployed:", address(autoPay));

        batchExecutor = new BatchExecutor(jobRegistry);
        console2.log("BatchExecutor Deployed:", address(batchExecutor));

        querier = new Querier(jobRegistry);
        console2.log("Querier Deployed:", address(querier));

        autoPayQuerier = new AutoPayQuerier(autoPay, querier);
        console2.log("AutoPayQuerier Deployed:", address(autoPayQuerier));

        payNFT = new PayNFT("PayNFT", "PNFT", address(autoPay), address(autoPayQuerier));
        console2.log("PayNFT Deployed:", address(payNFT));

        vm.stopBroadcast();
    }
}
