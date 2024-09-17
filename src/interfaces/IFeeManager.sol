// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeManager {
    function withdrawCollectedFees(address _token, address _recipient) external;
    function updateProtocolFeeRatio(uint8 _protocolFeeRatio) external;

    error NoFeesToWithdraw();
}
