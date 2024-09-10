// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @author Victor Brevig
contract ChainlinkOracle {
    AggregatorV3Interface internal ethUsdPriceFeed;
    uint8 internal ethPriceDecimals;
    uint256 updateThreshold;

    constructor(address _ethUsdPriceFeed, uint256 _updateThreshold) {
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        ethPriceDecimals = ethUsdPriceFeed.decimals();
        updateThreshold = _updateThreshold;
    }

    error FeedStale();

    function getPrice(address _token, bytes calldata _data) public view returns (uint256) {
        address feedAddress;
        assembly {
            feedAddress := calldataload(_data.offset)
        }

        uint8 tokenDecimals = ERC20(_token).decimals();

        // get ETH/USD price
        (, int256 ethPrice,, uint256 updatedAtEth,) = ethUsdPriceFeed.latestRoundData();
        AggregatorV3Interface feed = AggregatorV3Interface(feedAddress);
        // get token/USD price
        (, int256 tokenPrice,, uint256 updatedAtToken,) = feed.latestRoundData();

        uint256 threshold = block.timestamp - updateThreshold;

        if (updatedAtEth < threshold || updatedAtToken < threshold) revert FeedStale();

        uint8 tokenFeedDecimals = feed.decimals();

        uint8 scaleDecimals = ethPriceDecimals + tokenDecimals - tokenFeedDecimals;

        int256 price = (ethPrice * int256(10 ** scaleDecimals)) / tokenPrice;

        return uint256(price);
    }
}
