// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBatchExecutor {
    /**
     * @notice Processes a batch of subscriptions.
     * @notice Will not revert on failure of processing any single subscription, but will emit a FailedExecution event.
     */
    function executeBatch(uint256[] calldata _jobIndices, address _feeRecipient, bytes[] calldata _verificationData)
        external
        returns (Receipt[] memory);

    struct Receipt {
        uint256 jobIndex;
        uint256 executionFee;
        address executionFeeToken;
    }

    /**
     * @notice Thrown when processing a single subscription payment reverts.
     */
    event FailedExecution(uint256 jobIndex, bytes revertData);
}
