// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAutoPay {
    struct PaymentData {
        address recipient;
        uint256 amount;
        address token;
        bytes12 amountFactors;
    }

    event Payment(
        uint256 indexed index,
        address indexed sender,
        address indexed recipient,
        uint48 executionNumber,
        uint256 amount,
        address token,
        uint256 protocolFee,
        uint256 terms
    );
    event PaymentCreated(uint256 indexed index, address indexed recipient);
    event PaymentCanceled(uint256 indexed index, address indexed recipient);

    /// @notice Thrown when the caller is not the JobRegistry
    error NotJobRegistry();
}
