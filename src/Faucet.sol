// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

contract Faucet {
    // To fund an account with predefined tokens on base sepolia testnet.
    // These are created testnet tokens and have no value.
    using SafeTransferLib for ERC20;

    address public immutable WETH = 0xD72b476361bB087d8158235Cca3094900877361b;
    address public immutable USDC = 0x7139F4601480d20d43Fa77780B67D295805aD31a;
    address public immutable DAI = 0x701f372f2A10688c4f3e31E20ceabC1f3A88ac2c;
    address public immutable WBTC = 0xF671644C9e793caF69a45520B609DDD83611FE34;

    mapping(address => uint256) public lastDrip;

    constructor() {}

    function drip() public {
        uint256 lastDripTime = lastDrip[msg.sender];

        if (lastDripTime == 0) {
            lastDrip[msg.sender] = block.timestamp;
        } else if (block.timestamp - lastDripTime > 24 hours) {
            lastDrip[msg.sender] = block.timestamp;
        } else {
            revert("Can only drip once per day");
        }

        // 100 for every token (adjusted by decimals)
        ERC20(WETH).safeTransfer(msg.sender, 100000000000000000000);
        ERC20(USDC).safeTransfer(msg.sender, 100000000);
        ERC20(DAI).safeTransfer(msg.sender, 100000000000000000000);
        ERC20(WBTC).safeTransfer(msg.sender, 10000000000);
    }
}
