// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title Interface for the PriceOracle contract.
/// @author Victor Brevig
interface IPriceOracle {
    /// @notice Get the token/ETH price in wei.
    /// @param _token The token to get the price of.
    /// @param _data Additional data for the price oracle.
    /// @return price The price of the token in wei.
    function getPrice(address _token, bytes calldata _data) external view returns (uint256);
}
