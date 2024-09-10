// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @author stick
contract ERC20TokenTest is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialMint)
        ERC20(_name, _symbol, _decimals)
    {
        _mint(msg.sender, _initialMint);
    }
}
