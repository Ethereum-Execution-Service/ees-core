// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

contract FeeManager is IFeeManager, Owned {
    using SafeTransferLib for ERC20;

    // account => (token => balance) mapping of accumulated execution fees
    mapping(address => mapping(address => uint256)) public feeBalances;

    uint8 internal protocolFeeRatio;

    constructor(address _treasury, uint8 _protocolFeeRatio) Owned(_treasury) {
        protocolFeeRatio = _protocolFeeRatio;
    }

    /**
     * @notice Withdraws protocol fee from the contract.
     * @param _token The ERC-20 token to withdraw.
     * @param _recipient The address to receive the withdrawn tokens.
     */
    function withdrawCollectedFees(address _token, address _recipient) public override {
        uint256 amount = feeBalances[_recipient][_token];
        if (amount == 0) revert NoFeesToWithdraw();
        ERC20(_token).safeTransfer(_recipient, amount);
    }

    /**
     * @notice Updates protocol fee ratio.
     * @param _protocolFeeRatio The new protocol fee ratio.
     */
    function updateProtocolFeeRatio(uint8 _protocolFeeRatio) public override onlyOwner {
        protocolFeeRatio = _protocolFeeRatio;
    }
}
