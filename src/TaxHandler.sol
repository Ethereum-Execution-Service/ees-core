// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Owned} from "solmate/src/auth/Owned.sol";

/// @author Victor Brevig
/// @notice TaxHandler is responsible for handling tax updates for EES.
contract TaxHandler is Owned {
    uint256 internal lastProtocolTaxUpdate;
    uint256 internal lastExecutorTaxUpdate;
    uint256 internal constant protocolTaxUpdateCooldown = 7 days;
    uint256 internal constant executorTaxUpdateCooldown = 7 days;

    // 10%
    uint256 internal constant protocolTaxUpdateBps = 1_000;
    uint256 internal constant executorTaxUpdateBps = 1_000;

    uint256 internal protocolTax;
    uint256 internal executorTax;

    error TaxUpdateTooLarge();
    error UpdateOnCooldown();

    constructor(address _owner, uint256 _protocolTax, uint256 _executorTax) Owned(_owner) {
        lastProtocolTaxUpdate = block.timestamp;
        lastExecutorTaxUpdate = block.timestamp;
        protocolTax = _protocolTax;
        executorTax = _executorTax;
    }

    function updateProtocolTax(uint256 _protocolTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastProtocolTaxUpdate + protocolTaxUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _protocolTax > protocolTax ? _protocolTax - protocolTax : protocolTax - _protocolTax;

        uint256 maxDiff = protocolTax * protocolTaxUpdateBps / 10_000;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastProtocolTaxUpdate = block.timestamp;
        protocolTax = _protocolTax;
    }

    function updateExecutorTax(uint256 _executorTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastExecutorTaxUpdate + executorTaxUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _executorTax > executorTax ? _executorTax - executorTax : executorTax - _executorTax;
        uint256 maxDiff = executorTax * executorTaxUpdateBps / 10_000;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastExecutorTaxUpdate = block.timestamp;
        executorTax = _executorTax;
    }
}
