// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {AutoPay} from "../src/applications/AutoPay.sol";
import {JobRegistry} from "../src/JobRegistry.sol";
import {Querier} from "../src/Querier.sol";
import {AutoPayQuerier} from "../src/AutoPayQuerier.sol";

contract DeployQueriers is Script {
    function setUp() public {}

    function run() public returns (Querier querier, AutoPayQuerier autoPayQuerier) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        querier = new Querier(JobRegistry(0x39B7C79A5f64CFDc49B9fa516b0a05eE5E36ab53));
        console2.log("Querier Deployed:", address(querier));

        autoPayQuerier = new AutoPayQuerier(AutoPay(0xB939A10782B9F8D973CCB6827baa8eD924419706), querier);
        console2.log("AutoPayQuerier Deployed:", address(autoPayQuerier));

        vm.stopBroadcast();
    }
}
