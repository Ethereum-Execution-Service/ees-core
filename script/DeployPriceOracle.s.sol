// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {ChainlinkOracle} from "../src/priceOracles/ChainlinkOracle.sol";

contract DeployPriceOracle is Script {
    function setUp() public {}

    function run() public returns (ChainlinkOracle oracle) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        oracle = new ChainlinkOracle(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1, 86400);
        console2.log("ChainlinkOracle Deployed:", address(oracle));

        vm.stopBroadcast();
    }
}
