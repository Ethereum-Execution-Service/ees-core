// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IPriceOracle} from "../../../src/interfaces/IPriceOracle.sol";

contract DummyPriceOracle is IPriceOracle {
    uint256 public price;

    event AuxData(bytes auxData);

    constructor(uint256 _price) {
        price = _price;
    }

    function getPrice(address _token, bytes calldata _data) public view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}
