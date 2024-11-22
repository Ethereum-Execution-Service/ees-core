// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ModuleRegistry} from "./ModuleRegistry.sol";

/// @author Victor Brevig
/// @notice TaxHandler is responsible for handling tax updates for EES.
contract TaxHandler is ModuleRegistry {
    uint256 internal lastExecutionTaxUpdate;
    uint256 internal lastZeroFeeExecutionTaxUpdate;
    uint256 internal lastProtocolPoolCutUpdate;
    uint24 internal constant executionTaxUpdateCooldown = 7 days;
    uint24 internal constant zeroFeeExecutionTaxUpdateCooldown = 7 days;
    uint24 internal constant protocolPoolCutUpdateCooldown = 7 days;
    // 10%
    uint16 internal constant executionTaxUpdateBps = 1_000;
    // 10%
    uint16 internal constant protocolPoolCutUpdateBps = 1_000;

    uint256 internal executionTax; // in units of tax token
    uint256 internal zeroFeeExecutionTax; // in units of tax token
    uint256 internal protocolPoolCutBps; // in basis points (e.g. 1000 = 10%)
    uint256 internal constant BPS_DENOMINATOR = 10000; // 100% in basis points

    // maximum reward per execution in tax token. Should be updated when executionTax or protocolPoolCutBps are updated
    uint256 internal maxRewardPerExecution;



    error TaxUpdateTooLarge();
    error UpdateOnCooldown();

    constructor(address _owner, uint256 _executionTax, uint256 _zeroFeeExecutionTax, uint256 _protocolPoolCutBps) ModuleRegistry(_owner) {
        require(_protocolPoolCutBps < BPS_DENOMINATOR, "TaxHandler: protocol pool cut bps must be less than 100%");
        lastExecutionTaxUpdate = block.timestamp;
        executionTax = _executionTax;
        zeroFeeExecutionTax = _zeroFeeExecutionTax;
        lastProtocolPoolCutUpdate = block.timestamp;
        protocolPoolCutBps = _protocolPoolCutBps;
        maxRewardPerExecution = (executionTax * protocolPoolCutBps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Update the execution tax.
     * @notice Also updates maxRewardPerExecution accordingly.
     * @dev Can update executionTax at most executionTaxUpdateBps basis points every executionTaxUpdateCooldown seconds. 
     * @param _executionTax The new execution tax.
     */
    function updateExecutionTax(uint256 _executionTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastExecutionTaxUpdate + executionTaxUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _executionTax > executionTax ? _executionTax - executionTax : executionTax - _executionTax;
        uint256 maxDiff = executionTax * executionTaxUpdateBps / 10_000;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastExecutionTaxUpdate = block.timestamp;
        executionTax = _executionTax;
        maxRewardPerExecution = (executionTax * protocolPoolCutBps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Update the zero fee execution tax.
     * @dev Can update zeroFeeExecutionTax at most executionTaxUpdateBps basis points every zeroFeeExecutionTaxUpdateCooldown seconds. 
     * @param _zeroFeeExecutionTax The new zero fee execution tax.
     */
    function updateZeroFeeExecutionTax(uint256 _zeroFeeExecutionTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastZeroFeeExecutionTaxUpdate + zeroFeeExecutionTaxUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _zeroFeeExecutionTax > zeroFeeExecutionTax ? _zeroFeeExecutionTax - zeroFeeExecutionTax : zeroFeeExecutionTax - _zeroFeeExecutionTax;
        uint256 maxDiff = zeroFeeExecutionTax * executionTaxUpdateBps / 10_000;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastZeroFeeExecutionTaxUpdate = block.timestamp;
        zeroFeeExecutionTax = _zeroFeeExecutionTax;
    }

    /**
     * @notice Update the protocol pool cut bps.
     * @notice Also updates maxRewardPerExecution accordingly.
     * @dev Can update protocolPoolCutBps at most protocolPoolCutUpdateBps basis points every protocolPoolCutUpdateCooldown seconds. 
     * @param _protocolPoolCutBps The new protocol pool cut bps.
     */
    function updateProtocolPoolCutBps(uint256 _protocolPoolCutBps) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastProtocolPoolCutUpdate + protocolPoolCutUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _protocolPoolCutBps > protocolPoolCutBps ? _protocolPoolCutBps - protocolPoolCutBps : protocolPoolCutBps - _protocolPoolCutBps;
        uint256 maxDiff = protocolPoolCutBps * protocolPoolCutUpdateBps / 10_000;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastProtocolPoolCutUpdate = block.timestamp;
        protocolPoolCutBps = _protocolPoolCutBps;
        maxRewardPerExecution = (executionTax * protocolPoolCutBps) / BPS_DENOMINATOR;
    }

}
