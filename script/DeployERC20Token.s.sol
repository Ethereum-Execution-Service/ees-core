// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";
import {ERC20Token} from "../src/ERC20Token.sol";

contract DeployERC20Token is Script {
    string name;
    string symbol;
    uint8 decimals;
    address allowedMinter;

    function setUp() public {
        // set to treasury
        name = "TestToken";
        symbol = "TST";
        decimals = 18;
        // should be the BatchExecutor
        allowedMinter = address(0x12341234);
    }

    function run() public returns (ERC20Token erc20Token) {
        vm.startBroadcast();

        erc20Token = new ERC20Token(name, symbol, decimals, allowedMinter);
        console2.log("ERC20Token Deployed:", address(erc20Token));

        vm.stopBroadcast();
    }
}
