// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/src/console2.sol";
import "forge-std/src/Script.sol";

import {ERC20Token} from "../src/ERC20Token.sol";
import {ERC20TokenTest} from "../src/ERC20TokenTest.sol";

contract DeployERC20TestTokens is Script {
    // token
    string name;
    string symbol;
    uint8 decimals;

    function setUp() public {
        name = "RewardToken";
        symbol = "RWT";
        decimals = 18;
    }

    function run()
        public
        returns (ERC20TokenTest wethTest, ERC20TokenTest usdcTest, ERC20TokenTest daiTest, ERC20TokenTest wbtcTest)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // msg.sender recieves 1000_000 of each token

        wethTest = new ERC20TokenTest("Wrapped Ether", "WETH", 18, 1_000_000 * (10 ** 18));
        console2.log("WETH Deployed:", address(wethTest));

        usdcTest = new ERC20TokenTest("USD Coin", "USDC", 6, 1_000_000 * (10 ** 6));
        console2.log("USDC Deployed:", address(usdcTest));

        daiTest = new ERC20TokenTest("Dai Stablecoin", "DAI", 18, 1_000_000 * (10 ** 18));
        console2.log("DAI Deployed:", address(daiTest));

        wbtcTest = new ERC20TokenTest("Wrapped Bitcoin", "WBTC", 8, 1_000_000 * (10 ** 8));
        console2.log("WBTC Deployed:", address(wbtcTest));

        vm.stopBroadcast();
    }
}
