// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// move to periphery
interface IConfigProvider {
    function getConfig() external view returns (bytes memory, bytes memory, bytes memory);
}
