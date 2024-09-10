// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {PayNFT} from "../src/extras/PayNFT.sol";

contract DeployPayNFT is Script {
    function setUp() public {}

    function run() public returns (PayNFT payNFT) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        payNFT = new PayNFT(
            "PayNFT", "PNFT", 0xD0A88Cad352982BC16331a7b68edC841265D2c14, 0xF679caF95c6059e9DCE65559503A8D3C3B0093Be
        );
        console2.log("PayNFT Deployed:", address(payNFT));

        vm.stopBroadcast();
    }
}
