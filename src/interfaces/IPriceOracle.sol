// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title Interface for the PriceOracle contract.
interface IPriceOracle {
    /**
     * @notice Get the token/ETH price in wei.
     * @param _token The token to get the price of.
     * @param _data Additional data for the price oracle.
     * @return priceETH The price of the token in ETH in _token decimals. That is, number of tokens per ETH.
     * @return priceUSD the price of the token in USD in _token decimals. That is, number of tokens per USD.
     */
    function getPrice(address _token, bytes calldata _data) external view returns (uint256, uint256);
}
