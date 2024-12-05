// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITaxHandler {
    function updateExecutionTax(uint256 _executionTax) external;
    function updateZeroFeeExecutionTax(uint256 _zeroFeeExecutionTax) external;
    function updateProtocolPoolCutBps(uint256 _protocolPoolCutBps) external;
}
