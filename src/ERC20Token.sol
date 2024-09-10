// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @author Victor Brevig
contract ERC20Token is ERC20 {
    address public allowedMinter;

    error NotAllowedMinter();

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _allowedMinter)
        ERC20(_name, _symbol, _decimals)
    {
        allowedMinter = _allowedMinter;
    }

    function mint(address _to, uint256 _amount) external {
        // restrict to only permitted contract (the BatchExecutor)
        if (msg.sender != allowedMinter) revert NotAllowedMinter();
        _mint(_to, _amount);
    }
}
