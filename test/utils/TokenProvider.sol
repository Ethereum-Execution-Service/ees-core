// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TokenProvider {
    uint256 public constant MINT_AMOUNT_ERC20 = 100 ** 18;

    MockERC20 token0;
    MockERC20 token1;

    address faucet = address(0x98765);

    function initializeERC20Tokens() internal {
        token0 = new MockERC20("Test0", "TEST0", 6);
        token1 = new MockERC20("Test1", "TEST1", 18);
    }

    function setERC20TestTokens(address from) internal {
        token0.mint(from, MINT_AMOUNT_ERC20);
        token1.mint(from, MINT_AMOUNT_ERC20);
    }

    function setERC20TestTokenApprovals(Vm vm, address owner, address spender) internal {
        vm.startPrank(owner);
        token0.approve(spender, type(uint256).max);
        token1.approve(spender, type(uint256).max);
        vm.stopPrank();
    }
}
