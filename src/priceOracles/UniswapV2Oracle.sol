// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

import {UniswapV2Factory} from "lib/v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Pair} from "lib/v2-core/contracts/UniswapV2Pair.sol";

contract UniswapV2Oracle is IPriceOracle {
    UniswapV2Factory public factory;

    constructor(UniswapV2Factory _factory) public {
        factory = _factory;
    }

    function getPrice(address _token, bytes calldata _data) external view returns (uint256) {
        UniswapV2Pair pair = UniswapV2Pair(factory.getPair(_token, address(0)));

        if (_token == pair.token0()) {
            return pair.price0CumulativeLast();
        } else {
            return pair.price1CumulativeLast();
        }
    }
}
