// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ModuleRegistry} from "./ModuleRegistry.sol";
import {ITaxHandler} from "./interfaces/ITaxHandler.sol";

/**
 * @title TaxHandler
 * @notice Manages tax configuration and updates with rate limiting and cooldown periods
 * @dev Inherits from ModuleRegistry and Owned. Implements gradual tax updates with cooldowns
 *      to prevent sudden changes. All tax updates are limited to 10% per 7 days.
 */
contract TaxHandler is ModuleRegistry, ITaxHandler {
    /// @notice Timestamp of the last execution tax update
    uint256 internal lastExecutionTaxUpdate;

    /// @notice Timestamp of the last zero fee execution tax update
    uint256 internal lastZeroFeeExecutionTaxUpdate;

    /// @notice Timestamp of the last protocol pool cut update
    uint256 internal lastProtocolPoolCutUpdate;

    /// @notice Cooldown period for execution tax updates (7 days)
    uint24 internal constant executionTaxUpdateCooldown = 7 days;

    /// @notice Cooldown period for zero fee execution tax updates (7 days)
    uint24 internal constant zeroFeeExecutionTaxUpdateCooldown = 7 days;

    /// @notice Cooldown period for protocol pool cut updates (7 days)
    uint24 internal constant protocolPoolCutUpdateCooldown = 7 days;

    /// @notice Maximum percentage change for execution tax updates (10% in basis points)
    uint16 internal constant executionTaxUpdateBps = 1_000;

    /// @notice Maximum percentage change for protocol pool cut updates (10% in basis points)
    uint16 internal constant protocolPoolCutUpdateBps = 1_000;

    /// @notice Execution tax amount in staking token units
    uint256 internal executionTax;

    /// @notice Zero fee execution tax amount in staking token units
    uint256 internal zeroFeeExecutionTax;

    /// @notice Protocol pool cut in basis points (e.g., 1000 = 10%)
    uint256 internal protocolPoolCutBps;

    /// @notice Basis points denominator (10,000 = 100%)
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum reward per execution in staking token units
    /// @dev Calculated as executionTax * (BPS_DENOMINATOR - protocolPoolCutBps) / BPS_DENOMINATOR
    uint256 internal maxRewardPerExecution;

    error TaxUpdateTooLarge();
    error UpdateOnCooldown();

    /**
     * @notice Initializes the TaxHandler contract with initial tax configuration
     * @dev Sets initial tax values and calculates maxRewardPerExecution. Protocol pool cut must be less than 100%.
     * @param _owner Address that will own the contract (can update taxes)
     * @param _executionTax Initial execution tax amount
     * @param _zeroFeeExecutionTax Initial zero fee execution tax amount
     * @param _protocolPoolCutBps Initial protocol pool cut in basis points (must be < 10,000)
     */
    constructor(address _owner, uint256 _executionTax, uint256 _zeroFeeExecutionTax, uint256 _protocolPoolCutBps)
        ModuleRegistry(_owner)
    {
        require(_protocolPoolCutBps < BPS_DENOMINATOR, "TaxHandler: protocol pool cut bps must be less than 100%");
        lastExecutionTaxUpdate = block.timestamp;
        executionTax = _executionTax;
        zeroFeeExecutionTax = _zeroFeeExecutionTax;
        lastProtocolPoolCutUpdate = block.timestamp;
        protocolPoolCutBps = _protocolPoolCutBps;
        maxRewardPerExecution = (executionTax * (BPS_DENOMINATOR - protocolPoolCutBps)) / BPS_DENOMINATOR;
    }

    /**
     * @notice Updates the execution tax with rate limiting
     * @dev Can only be called by owner. Updates are limited to 10% change per 7 days.
     *      Automatically recalculates maxRewardPerExecution after update.
     * @param _executionTax New execution tax amount in staking token units
     * @custom:reverts UpdateOnCooldown if called before cooldown period has elapsed
     * @custom:reverts TaxUpdateTooLarge if change exceeds 10% of current value
     */
    function updateExecutionTax(uint256 _executionTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastExecutionTaxUpdate + executionTaxUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _executionTax > executionTax ? _executionTax - executionTax : executionTax - _executionTax;
        uint256 maxDiff = executionTax * executionTaxUpdateBps / BPS_DENOMINATOR;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastExecutionTaxUpdate = block.timestamp;
        executionTax = _executionTax;
        maxRewardPerExecution = (executionTax * (BPS_DENOMINATOR - protocolPoolCutBps)) / BPS_DENOMINATOR;
    }

    /**
     * @notice Updates the zero fee execution tax with rate limiting
     * @dev Can only be called by owner. Updates are limited to 10% change per 7 days.
     * @param _zeroFeeExecutionTax New zero fee execution tax amount in staking token units
     * @custom:reverts UpdateOnCooldown if called before cooldown period has elapsed
     * @custom:reverts TaxUpdateTooLarge if change exceeds 10% of current value
     */
    function updateZeroFeeExecutionTax(uint256 _zeroFeeExecutionTax) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastZeroFeeExecutionTaxUpdate + zeroFeeExecutionTaxUpdateCooldown) {
            revert UpdateOnCooldown();
        }

        uint256 diff = _zeroFeeExecutionTax > zeroFeeExecutionTax
            ? _zeroFeeExecutionTax - zeroFeeExecutionTax
            : zeroFeeExecutionTax - _zeroFeeExecutionTax;
        uint256 maxDiff = zeroFeeExecutionTax * executionTaxUpdateBps / BPS_DENOMINATOR;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastZeroFeeExecutionTaxUpdate = block.timestamp;
        zeroFeeExecutionTax = _zeroFeeExecutionTax;
    }

    /**
     * @notice Updates the protocol pool cut with rate limiting
     * @dev Can only be called by owner. Updates are limited to 10% change per 7 days.
     *      Automatically recalculates maxRewardPerExecution after update.
     * @param _protocolPoolCutBps New protocol pool cut in basis points (e.g., 1000 = 10%)
     * @custom:reverts UpdateOnCooldown if called before cooldown period has elapsed
     * @custom:reverts TaxUpdateTooLarge if change exceeds 10% of current value
     */
    function updateProtocolPoolCutBps(uint256 _protocolPoolCutBps) public onlyOwner {
        // can change value at most X percent every Y time
        if (block.timestamp < lastProtocolPoolCutUpdate + protocolPoolCutUpdateCooldown) revert UpdateOnCooldown();

        uint256 diff = _protocolPoolCutBps > protocolPoolCutBps
            ? _protocolPoolCutBps - protocolPoolCutBps
            : protocolPoolCutBps - _protocolPoolCutBps;
        uint256 maxDiff = protocolPoolCutBps * protocolPoolCutUpdateBps / BPS_DENOMINATOR;
        if (diff > maxDiff) revert TaxUpdateTooLarge();

        lastProtocolPoolCutUpdate = block.timestamp;
        protocolPoolCutBps = _protocolPoolCutBps;
        maxRewardPerExecution = (executionTax * (BPS_DENOMINATOR - protocolPoolCutBps)) / BPS_DENOMINATOR;
    }
}
